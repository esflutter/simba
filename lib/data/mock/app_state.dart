import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart' show PocketBase;

import '../../core/config/env.dart';
import '../../features/create_order/order_draft.dart';
import '../../features/reviews/reviews_providers.dart'
    show myReviewedOrderIdsProvider;
import '../local/preferences_store.dart';
import '../models/models.dart';
import '../remote/pocketbase_client.dart';
import 'mock_data.dart';

/// Sentinel для nullable-полей в [AppState.copyWith]. Передача `null`
/// явно (`copyWith(user: null)`) раньше игнорировалась через `?? this.user`
/// — нельзя было обнулить поле через copyWith, приходилось собирать новый
/// AppState вручную (как в `logout`). Теперь: пропущенный аргумент
/// оставляет старое значение, явный `null` — стирает.
const _appStateSentinel = Object();

@immutable
class AppState {
  const AppState({
    required this.user,
    required this.role,
    required this.orders,
    required this.myOrders,
    required this.reviews,
    required this.selectedCityId,
    required this.executorActive,
    required this.onboardingSeen,
  });

  final AppUser? user;
  final UserRole role;
  final List<Order> orders;
  final List<Order> myOrders;
  final List<Review> reviews;
  final String? selectedCityId;
  final bool executorActive;
  /// «Пользователь устройства уже видел онбординг». После первого
  /// прохождения остаётся true до полного wipe приложения — повторно
  /// онбординг не показывается даже после logout.
  final bool onboardingSeen;

  City get selectedCity {
    final id = selectedCityId;
    if (id == null) return MockData.cities.first;
    for (final c in MockData.cities) {
      if (c.id == id) return c;
    }
    // Сохранённый cityId не нашёлся в локальном справочнике — обычно это
    // означает рассинхронизацию: либо список миллионников на бэке расширили,
    // либо юзер выбирал город через DaData и его id отсутствует в моках.
    // Раньше подменяли первой записью молча; теперь debugPrint, чтобы такие
    // случаи всплывали в логах, и юзер хотя бы видит «Москву», а не пустой
    // экран. На уровне UI оборачивать в null/«Не выбран» дороже, чем
    // полезного эффекта.
    if (kDebugMode) {
      debugPrint(
          '[AppState] selectedCity: id "$id" not in MockData.cities — '
          'fallback to ${MockData.cities.first.name}');
    }
    return MockData.cities.first;
  }

  AppState copyWith({
    Object? user = _appStateSentinel,
    UserRole? role,
    List<Order>? orders,
    List<Order>? myOrders,
    List<Review>? reviews,
    Object? selectedCityId = _appStateSentinel,
    bool? executorActive,
    bool? onboardingSeen,
  }) =>
      AppState(
        user: identical(user, _appStateSentinel)
            ? this.user
            : user as AppUser?,
        role: role ?? this.role,
        orders: orders ?? this.orders,
        myOrders: myOrders ?? this.myOrders,
        reviews: reviews ?? this.reviews,
        selectedCityId: identical(selectedCityId, _appStateSentinel)
            ? this.selectedCityId
            : selectedCityId as String?,
        executorActive: executorActive ?? this.executorActive,
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      );
}

class AppController extends Notifier<AppState> {
  PreferencesStore? get _prefs {
    try {
      return ref.read(preferencesProvider);
    } catch (_) {
      return null; // тесты могут не подменять prefs — это допустимо
    }
  }

  @override
  AppState build() {
    final p = _prefs;
    final cityId = p?.cityId;
    final city = cityId == null
        ? MockData.cities.first
        : MockData.cities.firstWhere(
            (c) => c.id == cityId,
            orElse: () {
              if (kDebugMode) {
                debugPrint(
                    '[AppState.build] saved cityId "$cityId" not in mocks — '
                    'fallback to ${MockData.cities.first.name}');
              }
              return MockData.cities.first;
            },
          );
    return AppState(
      user: p?.user,
      role: p?.role ?? UserRole.customer,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(city.center),
      myOrders: Env.hasPocketbase
          ? const []
          : _withoutExpiredOpen(MockData.seedMyOrders(city.center)),
      reviews: Env.hasPocketbase ? const [] : MockData.seedReviews(),
      selectedCityId: cityId,
      executorActive: false,
      onboardingSeen: p?.onboardingSeen ?? false,
    );
  }

  /// Помечаем онбординг как пройденный. Флаг сохраняется в prefs пожизненно
  /// (на устройство), чтобы logout не возвращал юзера к экрану онбординга.
  /// Возвращает Future, чтобы вызывающий мог дождаться записи в prefs
  /// перед навигацией — иначе при быстром переходе на /city и cold restart
  /// прямо после онбординга флаг может не успеть сохраниться.
  Future<void> markOnboardingSeen() async {
    if (state.onboardingSeen) return;
    state = state.copyWith(onboardingSeen: true);
    final fut = _prefs?.setOnboardingSeen(true);
    if (fut != null) {
      try {
        await fut;
      } catch (_) {
        // Запись в prefs упала — state уже обновлён, на этом устройстве
        // в текущей сессии онбординг показываться не будет. На следующий
        // cold start, если ситуация повторится, юзер увидит онбординг
        // снова — терпимо.
      }
    }
  }

  /// Отбрасывает «размещённые» заказы, которые должны исчезнуть:
  ///   1) назначенная дата уже прошла, а исполнитель так и не выбран
  ///      ([Order.isExpiredOpen]);
  ///   2) с момента публикации прошло 30 дней, исполнитель не выбран
  ///      ([Order.isStaleOpenWithoutExecutor]) — продуктовое правило:
  ///      такие заказы удаляются целиком, без следа.
  /// На бэке физическим удалением занимается крон-задача; здесь —
  /// клиентская сетка безопасности, чтобы протухший заказ не «всплыл»
  /// в ленте на устройстве, которое давно не открывали.
  List<Order> _withoutExpiredOpen(List<Order> orders) => orders
      .where((o) => !o.isExpiredOpen && !o.isStaleOpenWithoutExecutor)
      .toList();

  /// Идентификатор города, который ждёт синка с бэком. Пока он не null,
  /// `_consumeAuthEnvelope` НЕ перезатирает selectedCityId из record —
  /// иначе fire-and-forget PATCH мог быть перезаписан ответом authRefresh,
  /// прилетевшим раньше, чем дойдёт сам PATCH.
  ///
  /// `_citySyncSeq` — счётчик, который растёт при каждом setCity. Когда
  /// приходит ответ от PATCH, он сбрасывает `_pendingCitySync` только если
  /// его seq совпадает с текущим. Без счётчика три быстрых переключения
  /// порождали три fire-and-forget запроса, и поздний (с устаревшим city)
  /// мог стереть pending‑флаг для последующего PATCH.
  ///
  /// Публичный getter [pendingCitySync] читает `auth_repository`, чтобы
  /// при `_consumeAuthEnvelope` не перетереть `selectedCityId` тем
  /// значением, которое прилетит из authRefresh раньше, чем дойдёт PATCH.
  String? _pendingCitySync;
  String? get pendingCitySync => _pendingCitySync;
  int _citySyncSeq = 0;

  void setCity(String id) {
    final prevCity = state.selectedCityId;
    // Short-circuit: тот же город — не пересоздаём seed моков и не шлём
    // лишний PATCH. До этого тап на свой же текущий город обнулял
    // моковую myOrders на дефолтный seed и слал бесполезный запрос.
    if (prevCity == id) return;

    final c = MockData.cities.firstWhere((c) => c.id == id);
    state = state.copyWith(
      selectedCityId: id,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(c.center),
      myOrders: Env.hasPocketbase
          ? const []
          : _withoutExpiredOpen(MockData.seedMyOrders(c.center)),
    );
    _prefs?.setCityId(id);

    // Сбрасываем адрес в драфте создания заказа при смене города. Раньше
    // юзер вводил адрес в Москве, переключал город на Питер и упирался
    // на summary в city-guard «адрес не в вашем городе» — после того,
    // как уже прошёл весь wizard. Тут сбрасываем рано.
    if (prevCity != null && prevCity.isNotEmpty) {
      try {
        ref.read(orderDraftProvider.notifier).clearAddress();
      } catch (_) {
        // ok если provider не зарегистрирован (тесты).
      }
    }

    // Live-режим: PATCH users.city → источник правды на бэке. Помечаем
    // city как «в полёте», чтобы _consumeAuthEnvelope не сбросил локальный
    // выбор, если до завершения PATCH прилетит authRefresh со старым city.
    // По завершении (успех или ошибка) — снимаем флаг ТОЛЬКО если это
    // ответ на последний выпущенный запрос (по seq), иначе ранние
    // ответы стирали бы pending-state ещё-в-пути запросов.
    if (Env.hasPocketbase) {
      try {
        final pb = ref.read(pocketbaseProvider);
        final me = pb?.authStore.record;
        if (pb != null && pb.authStore.isValid && me != null) {
          final mySeq = ++_citySyncSeq;
          _pendingCitySync = id;
          void clearIfLatest() {
            if (_citySyncSeq == mySeq) _pendingCitySync = null;
          }
          pb
              .collection('users')
              .update(me.id, body: {'city': id})
              .then((_) => clearIfLatest())
              // ignore: body_might_complete_normally_catch_error
              .catchError((_) => clearIfLatest());
        }
      } catch (_) {
        // ref.read may throw in tests without PB override — игнор.
      }
    }
  }

  void completeAuth({required String phone}) {
    final u = AppUser(
      id: 'me',
      name: '',
      phone: phone,
      rating: 0,
      reviewsCount: 0,
      cityId: state.selectedCityId,
    );
    state = state.copyWith(user: u);
    _prefs?.saveUser(u);
  }

  /// Принять авторизованного пользователя из PocketBase (после verify SMS).
  /// Сохраняем как локальный стейт — остальные экраны продолжают читать
  /// `state.user` без изменений.
  void completeAuthRemote(AppUser user) {
    state = state.copyWith(user: user);
    _prefs?.saveUser(user);
  }

  void completeProfile({
    required String name,
    String? photoPath,
    bool? hasTools,
    bool? hasTransport,
  }) {
    final u = state.user;
    if (u == null) return;
    final updated = u.copyWith(
      name: name.trim().isEmpty ? 'Без имени' : name,
      photoPath: photoPath,
      hasTools: hasTools,
      hasTransport: hasTransport,
    );
    state = state.copyWith(user: updated);
    _prefs?.saveUser(updated);
  }

  void setRole(UserRole role) {
    state = state.copyWith(role: role);
    _prefs?.setRole(role);
    // При переключении в роль исполнителя — регистрируем «онлайн» на бэке,
    // чтобы push'и `new_order_nearby` начали приходить. При обратном
    // переключении в заказчика — гасим флаг.
    _syncExecutorStatus(role == UserRole.executor);
  }

  /// То же, что `setRole`, но БЕЗ обратного пуша на сервер. Нужно когда
  /// мы только что прочитали серверное значение и хотим зафиксировать
  /// его локально — пушить тот же флаг обратно бессмысленно и может
  /// поймать гонку с параллельным изменением на другом устройстве.
  void adoptRoleFromServer(UserRole role) {
    if (state.role == role) return;
    state = state.copyWith(role: role);
    _prefs?.setRole(role);
  }

  /// Локально установить `executorActive` БЕЗ пуша на сервер. Используется
  /// при бутстрапе: на cold-start state.executorActive всегда = false (не
  /// сохраняется в prefs), но на сервере флаг мог остаться true — если
  /// юзер закрыл приложение в режиме «Готов помочь». Без этой подтяжки
  /// тумблер в UI показывал OFF, а push-сегмент на бэке продолжал
  /// считать юзера активным и рассылать ему `new_order_nearby`.
  void adoptExecutorActiveFromServer(bool active) {
    if (state.executorActive == active) return;
    state = state.copyWith(executorActive: active);
  }

  void setExecutorActive(bool active) {
    state = state.copyWith(executorActive: active);
    _syncExecutorStatus(active);
  }

  /// Шлёт `/api/me/executor-status` на бэк. Fire-and-forget: ошибки лога —
  /// сетевые ошибки не должны блокировать смену роли в UI. Если есть PB —
  /// запрашивает текущие координаты через geolocator (без блокировки UI),
  /// и шлёт их вместе с флагом.
  void _syncExecutorStatus(bool isActive) {
    final PocketBase pb;
    try {
      final maybe = ref.read(pocketbaseProvider);
      if (maybe == null) return;
      pb = maybe;
    } catch (_) {
      // `pocketbaseProvider` бросает UnimplementedError, если контейнер
      // не переопределил его (unit-тесты). В этом случае sync некуда
      // отсылать — просто ничего не делаем.
      return;
    }
    () async {
      double? lat;
      double? lng;
      if (isActive) {
        try {
          final perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 8),
              ),
            );
            lat = pos.latitude;
            lng = pos.longitude;
          }
        } catch (_) {/* нет permission или таймаут — шлём без координат */}
      }
      // Пока ловили GPS, юзер мог сделать logout — токен уже пуст и сервер
      // ответит 401, засоряя логи. Перепроверяем `isValid` прямо перед
      // запросом, а не только при входе в функцию.
      if (!pb.authStore.isValid || pb.authStore.token.isEmpty) return;
      try {
        await sharedHttpClient
            .post(
              Uri.parse('${pb.baseURL}/api/me/executor-status'),
              headers: {
                // Bearer-префикс обязателен: без него PB 0.22+ трактует
                // запрос как анонимный, флаг is_active_executor никогда
                // не апдейтится. Симметрично исправлено в auth_repository.
                'Authorization': 'Bearer ${pb.authStore.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'is_active': isActive,
                // ignore: use_null_aware_elements
                if (lat != null) 'lat': lat,
                // ignore: use_null_aware_elements
                if (lng != null) 'lng': lng,
              }),
            )
            // Без таймаута запрос на медленной сети висит до системного
            // таймаута сокета (60+ сек). При быстром переключении роли
            // в фоне копились зависшие запросы, забивающие HTTP-клиент.
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        // $e может содержать body запроса: lat/lng координаты пользователя.
        // В release не пишем — иначе они утекают в logcat.
        if (kDebugMode) {
          debugPrint('[executor-status] sync failed: $e');
        }
      }
    }();
  }

  void createOrder(Order order) {
    state = state.copyWith(myOrders: [order, ...state.myOrders]);
  }

  void cancelOrder(String id) {
    // Отмена заказа заказчиком = полное удаление записи. По ТЗ-схеме:
    // «Заказчик может отказаться → Заказ исчезает» (без оговорок про
    // статус — и до accept, и после). На live это `delete` на бэке;
    // соответствующее правило `deleteRule` должно покрывать `open` +
    // `accepted` (пока стороны не отметили свою часть).
    final target = state.myOrders.where((o) => o.id == id).toList();
    if (target.isEmpty) return;
    final o = target.first;
    final canDelete = o.status == OrderStatus.open ||
        (o.status == OrderStatus.accepted && o.canCancelByCustomer());
    if (!canDelete) return;
    state = state.copyWith(
      myOrders: state.myOrders.where((x) => x.id != id).toList(),
    );
  }

  void acceptResponse(String orderId, String executorId) {
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) {
            if (o.id != orderId) return o;
            // Сохраняем ВСЕ отклики, не схлопываем в [executorId]: если
            // принятый исполнитель потом откажется (`releaseOrderAsExecutor`),
            // мы возвращаем заказ в open с прежними кандидатами. На бэке
            // это отдельная коллекция order_responses со статусами — она
            // не теряется. До этого мок отбрасывал чужие отклики, и
            // поведение mock vs live расходилось.
            //
            // Гарантируем, что executorId есть в списке: вдруг его там
            // не было (например, на старте теста). Дубль исключаем через
            // toSet → list (порядок не важен — UI сортирует/группирует).
            final newResponses = {...o.responses, executorId}.toList();
            return o.copyWith(
              executorId: executorId,
              status: OrderStatus.accepted,
              responses: newResponses,
            );
          })
          .toList(),
    );
  }

  /// Отклонить отклик от конкретного пользователя — убрать его из responses.
  /// Заказ остаётся открытым, остальные отклики не трогаем.
  void declineResponse(String orderId, String userId) {
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) => o.id == orderId
              ? o.copyWith(
                  responses: o.responses.where((id) => id != userId).toList(),
                )
              : o)
          .toList(),
    );
  }

  /// Исполнитель ('me') откликается на open-заказ. Заказ остаётся в статусе
  /// open, в responses добавляется 'me'. Заказчик потом выбирает кого принять.
  void takeOrderAsExecutor(String orderId) {
    // Защита: нельзя откликаться на собственный заказ. На бэке это закрывает
    // фильтр /api/orders/feed (customer != me) + правило order_responses
    // createRule, но клиентскую защиту тоже держим — если бэк-фильтр сломается
    // или заказ окажется в state.orders по ошибке, мы не позволим отправить
    // запрос, который всё равно отвалится 403.
    final mine = state.myOrders.any((o) => o.id == orderId);
    if (mine) return;
    state = state.copyWith(
      orders: state.orders.map((o) {
        if (o.id != orderId) return o;
        if (o.responses.contains('me')) return o; // повторный отклик
        return o.copyWith(responses: [...o.responses, 'me']);
      }).toList(),
    );
  }

  /// Исполнитель отказывается от принятого заказа — заказ возвращается в
  /// ленту со статусом open и сброшенным executor. Чужие отклики
  /// сохраняются (теперь acceptResponse не схлопывает список); удаляем
  /// только свой ('me'), чтобы при возврате в ленту его карточка не
  /// показывала «уже откликнулся».
  ///
  /// На бэке этим занимается hook accepted→open в main.pb.js: он
  /// возвращает declined-отклики в pending и ставит relisted_at = now
  /// (миграция 028) — сбрасывает 30-дневный счётчик авто-удаления.
  /// На моках relistedAt не выставляем — нет таймера, который от него
  /// зависит, а тесты не покрывают цикл «accept → release → автоудаление».
  void releaseOrderAsExecutor(String orderId) {
    state = state.copyWith(
      orders: state.orders.map((o) {
        if (o.id != orderId) return o;
        // Guard: только `accepted` без отметок — иначе ничего не делаем.
        // UI скрывает кнопку через `Order.canCancelByExecutor()`, но
        // защитный гард не повредит против гонок / тестов.
        if (o.status != OrderStatus.accepted ||
            o.workConfirmedAt != null ||
            o.paymentReceivedAt != null) {
          return o;
        }
        return o.copyWith(
          status: OrderStatus.open,
          executorId: null,
          responses: o.responses.where((id) => id != 'me').toList(),
        );
      }).toList(),
    );
  }

  /// Заказчик отмечает «работа выполнена». На моках ставим
  /// `workConfirmedAt = now`. Если исполнитель уже отметил свою часть
  /// (`paymentReceivedAt != null`) — заказ переходит в `completed`.
  /// Реализует левую ветвь правой части схемы ТЗ («Заказчик может
  /// отметить, что работа выполнена → в историю заказчика»).
  ///
  /// На live этим занимается серверный hook (по факту трёх timestamps).
  void markCustomerCompleted(String orderId) =>
      _applyCompletionMark(orderId, isCustomer: true);

  /// Исполнитель отмечает «оплата получена». Симметрично
  /// [markCustomerCompleted]: если заказчик уже отметил свою часть —
  /// заказ переходит в `completed`.
  void markExecutorCompleted(String orderId) =>
      _applyCompletionMark(orderId, isCustomer: false);

  /// Общая реализация для обеих сторон. Раньше была копипаста на 60 строк
  /// с одинаковой логикой; разница только в том, какой timestamp ставится
  /// и каким сравнением проверяется «другая сторона уже отметила».
  /// Обновляем И `myOrders`, И `orders` — один и тот же заказ ID
  /// присутствует ровно в одной коллекции (по реальной схеме), но
  /// прохождение по обеим коллекциям дешевле, чем гадать, в какой он.
  ///
  /// Guard'ы:
  ///   1. Только `accepted` — отметить уже завершённый / отменённый /
  ///      открытый заказ нельзя.
  ///   2. Время заказа уже наступило (`isTimeArrived`). По ТЗ — кнопки
  ///      «Отметить ...» доступны только ПОСЛЕ scheduledAt. UI это
  ///      уже скрывает, но контроллер не должен полагаться на UI:
  ///      прямой вызов из теста / в гонке должен отвалиться.
  void _applyCompletionMark(String orderId, {required bool isCustomer}) {
    final now = DateTime.now();
    Order patch(Order o) {
      if (o.id != orderId) return o;
      if (o.status != OrderStatus.accepted) return o;
      if (!o.isTimeArrived) return o;
      // Уже отмечено этой стороной — идемпотентный no-op, не перетираем
      // первоначальный timestamp.
      final mySideAlready = isCustomer
          ? o.workConfirmedAt != null
          : o.paymentReceivedAt != null;
      if (mySideAlready) return o;
      final otherSideAt =
          isCustomer ? o.paymentReceivedAt : o.workConfirmedAt;
      final bothDone = otherSideAt != null;
      return o.copyWith(
        workConfirmedAt: isCustomer ? now : o.workConfirmedAt,
        paymentReceivedAt: isCustomer ? o.paymentReceivedAt : now,
        workDoneAt: o.workDoneAt ?? now,
        status: bothDone ? OrderStatus.completed : o.status,
        completedAt: bothDone ? now : o.completedAt,
      );
    }

    state = state.copyWith(
      myOrders: state.myOrders.map(patch).toList(),
      orders: state.orders.map(patch).toList(),
    );
  }

  /// Сохранить отзыв «от меня» о другом участнике заказа.
  void addReview({
    required String orderId,
    required String toUserId,
    required int rating,
    required String comment,
    required List<String> tags,
  }) {
    final review = Review(
      id: _generateMockId('r'),
      fromUserId: 'me',
      toUserId: toUserId,
      orderId: orderId,
      rating: rating,
      comment: comment,
      tags: tags,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(reviews: [review, ...state.reviews]);
  }

  /// Генерация ID для мок-сущности: epoch-микросекунды + 32 бита random.
  /// Раньше использовался только `microsecondsSinceEpoch` — теоретически
  /// два события в одной микросекунде давали бы одинаковый id (особенно
  /// в автотестах с быстрыми тапами или Future.wait).
  String _generateMockId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = _idRandom.nextInt(1 << 32).toRadixString(36);
    return '${prefix}_${ts}_$rnd';
  }

  static final Random _idRandom = Random();

  void logout() {
    // При logout сохраняем cityId и onboardingSeen — это устройство-локальные
    // флаги, не привязанные к юзеру. Логика «уже видел онбординг» и «выбрал
    // город» переживает logout, чтобы юзер на этом устройстве при следующем
    // входе сразу шёл на /auth/phone, без повторного онбординга и выбора.
    // Если при новом логине бэк пришлёт users.city — он перепишет локальный
    // (см. auth_repository._consumeAuthEnvelope).
    final keepCityId = state.selectedCityId;
    final city = state.selectedCity;
    // Сбрасываем «в полёте PATCH города» — даже если он не дошёл, после
    // logout его уже некуда применять, и блокировать будущий
    // _consumeAuthEnvelope от перезаписи неправильно.
    _pendingCitySync = null;
    state = AppState(
      user: null,
      role: UserRole.customer,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(city.center),
      myOrders:
          Env.hasPocketbase ? const [] : MockData.seedMyOrders(city.center),
      reviews: Env.hasPocketbase ? const [] : MockData.seedReviews(),
      selectedCityId: keepCityId,
      executorActive: false,
      onboardingSeen: state.onboardingSeen,
    );
    _prefs?.clearUser();
    _prefs?.setRole(UserRole.customer);
    // Чистим черновик создания заказа: иначе адрес/категория/фото из
    // прошлой сессии (потенциально с PII — для-кого телефон, фото)
    // подтянутся в новом юзере на этом устройстве. AuthRepository.logout()
    // делает то же самое для live-режима через провайдер — мы дублируем
    // для мок-режима, где auth_repository.logout не вызывается.
    try {
      ref.read(orderDraftProvider.notifier).reset();
    } catch (_) {
      // ok если provider не зарегистрирован в текущем scope (юнит-тесты).
    }
    // Мок-логаут НЕ вызывает auth_repository.logout(), поэтому
    // инвалидируем те провайдеры, которые там чистятся, и здесь.
    // Без этого «по каким заказам я уже оставил отзыв» (не-autoDispose)
    // переживает logout и при следующем юзере на том же устройстве
    // показывает кнопку «Оставить отзыв» по заказам прошлой сессии.
    try {
      ref.invalidate(myReviewedOrderIdsProvider);
    } catch (_) {/* ok в тестах */}
  }
}

final appControllerProvider =
    NotifierProvider<AppController, AppState>(AppController.new);

/// Поиск юзера по id в локальных моках. Если id неизвестен — возвращает
/// nullable. Раньше fallback был на `MockData.demoCurrentUser` («Иван
/// Иванов» с рейтингом 4.9), и в live-режиме контрагент любого PB-id
/// отображался как этот мок-юзер; для отзывов это превращалось в
/// «я оставил отзыв сам себе»-эффект. UI должен сам решать что показать
/// для unknown (имя из expand, обезличенное «Пользователь» и т.п.).
AppUser? userById(String id) {
  if (id == 'me') return MockData.demoCurrentUser;
  for (final u in MockData.otherUsers) {
    if (u.id == id) return u;
  }
  return null;
}

LatLng locationOf(City city) => city.center;
