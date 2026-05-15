import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../features/create_order/order_draft.dart';
import '../local/preferences_store.dart';
import '../models/models.dart';
import '../remote/pocketbase_client.dart';
import 'mock_data.dart';

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
    required this.searchRadiusKm,
    required this.onboardingSeen,
  });

  final AppUser? user;
  final UserRole role;
  final List<Order> orders;
  final List<Order> myOrders;
  final List<Review> reviews;
  final String? selectedCityId;
  final bool executorActive;
  final double searchRadiusKm;
  /// «Пользователь устройства уже видел онбординг». После первого
  /// прохождения остаётся true до полного wipe приложения — повторно
  /// онбординг не показывается даже после logout.
  final bool onboardingSeen;

  City get selectedCity => MockData.cities.firstWhere(
        (c) => c.id == selectedCityId,
        orElse: () => MockData.cities.first,
      );

  AppState copyWith({
    AppUser? user,
    UserRole? role,
    List<Order>? orders,
    List<Order>? myOrders,
    List<Review>? reviews,
    String? selectedCityId,
    bool? executorActive,
    double? searchRadiusKm,
    bool? onboardingSeen,
  }) =>
      AppState(
        user: user ?? this.user,
        role: role ?? this.role,
        orders: orders ?? this.orders,
        myOrders: myOrders ?? this.myOrders,
        reviews: reviews ?? this.reviews,
        selectedCityId: selectedCityId ?? this.selectedCityId,
        executorActive: executorActive ?? this.executorActive,
        searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
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
        : MockData.cities.firstWhere((c) => c.id == cityId,
            orElse: () => MockData.cities.first);
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
      searchRadiusKm: 5,
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

  /// Отбрасывает «размещённые» заказы, у которых истекла назначенная дата
  /// и так и не нашёлся исполнитель — они автоматически удаляются.
  List<Order> _withoutExpiredOpen(List<Order> orders) =>
      orders.where((o) => !o.isExpiredOpen).toList();

  /// Идентификатор города, который ждёт синка с бэком. Пока он не null,
  /// `_consumeAuthEnvelope` НЕ перезатирает selectedCityId из record —
  /// иначе fire-and-forget PATCH мог быть перезаписан ответом authRefresh,
  /// прилетевшим раньше, чем дойдёт сам PATCH.
  String? _pendingCitySync;
  String? get pendingCitySync => _pendingCitySync;

  void setCity(String id) {
    final prevCity = state.selectedCityId;
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
    if (prevCity != null && prevCity.isNotEmpty && prevCity != id) {
      try {
        ref.read(orderDraftProvider.notifier).clearAddress();
      } catch (_) {
        // ok если provider не зарегистрирован (тесты).
      }
    }

    // Live-режим: PATCH users.city → источник правды на бэке. Помечаем
    // city как «в полёте», чтобы _consumeAuthEnvelope не сбросил локальный
    // выбор, если до завершения PATCH прилетит authRefresh со старым city.
    // По завершении (успех или ошибка) — снимаем флаг.
    if (Env.hasPocketbase) {
      try {
        final pb = ref.read(pocketbaseProvider);
        if (pb != null &&
            pb.authStore.isValid &&
            pb.authStore.record != null) {
          _pendingCitySync = id;
          pb
              .collection('users')
              .update(pb.authStore.record!.id, body: {'city': id})
              .then((_) {
            if (_pendingCitySync == id) _pendingCitySync = null;
          })
              // ignore: body_might_complete_normally_catch_error
              .catchError((_) {
            if (_pendingCitySync == id) _pendingCitySync = null;
          });
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
      name: name.trim().isEmpty ? 'Пользователь' : name,
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

  void setExecutorActive(bool active) {
    state = state.copyWith(executorActive: active);
    _syncExecutorStatus(active);
  }

  /// Шлёт `/api/me/executor-status` на бэк. Fire-and-forget: ошибки лога —
  /// сетевые ошибки не должны блокировать смену роли в UI. Если есть PB —
  /// запрашивает текущие координаты через geolocator (без блокировки UI),
  /// и шлёт их вместе с флагом.
  void _syncExecutorStatus(bool isActive) {
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
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
      try {
        await sharedHttpClient.post(
          Uri.parse('${pb.baseURL}/api/me/executor-status'),
          headers: {
            'Authorization': pb.authStore.token,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'is_active': isActive,
            // ignore: use_null_aware_elements
            if (lat != null) 'lat': lat,
            // ignore: use_null_aware_elements
            if (lng != null) 'lng': lng,
          }),
        );
      } catch (e) {
        debugPrint('[executor-status] sync failed: $e');
      }
    }();
  }

  void setSearchRadius(double km) {
    state = state.copyWith(searchRadiusKm: km);
  }

  void createOrder(Order order) {
    state = state.copyWith(myOrders: [order, ...state.myOrders]);
  }

  void cancelOrder(String id) {
    // Удалить (= отменить «без следа») можно ТОЛЬКО размещённый заказ.
    // После того как заказчик принял исполнителя, заказ остаётся в системе
    // до завершения цикла FSM (markWorkDone → confirmPayment → completed)
    // или до автоматического закрытия по no-show через cron.
    final target = state.myOrders.where((o) => o.id == id).toList();
    if (target.isEmpty) return;
    if (target.first.status != OrderStatus.open) return;
    state = state.copyWith(
      myOrders: state.myOrders.where((o) => o.id != id).toList(),
    );
  }

  void acceptResponse(String orderId, String executorId) {
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) => o.id == orderId
              ? o.copyWith(
                  executorId: executorId,
                  status: OrderStatus.accepted,
                  responses: [executorId],
                )
              : o)
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
  /// ленту со статусом open и сброшенным executor. На моках сценарий почти
  /// гипотетический (моковая лента не показывает accepted чужих заказов),
  /// но логика симметрична `takeOrderAsExecutor` ради консистентности
  /// FSM в офлайн-демо.
  void releaseOrderAsExecutor(String orderId) {
    state = state.copyWith(
      orders: state.orders.map((o) {
        if (o.id != orderId) return o;
        return o.copyWith(
          status: OrderStatus.open,
          executorId: null,
          responses: o.responses.where((id) => id != 'me').toList(),
        );
      }).toList(),
    );
  }

  void markWorkDone(String orderId, {required bool inMyOrders}) {
    if (inMyOrders) {
      state = state.copyWith(
        myOrders: state.myOrders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.awaitingPayment) : o)
            .toList(),
      );
    } else {
      state = state.copyWith(
        orders: state.orders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.awaitingPayment) : o)
            .toList(),
      );
    }
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
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
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

  void confirmPayment(String orderId, {required bool inMyOrders}) {
    if (inMyOrders) {
      state = state.copyWith(
        myOrders: state.myOrders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.completed) : o)
            .toList(),
      );
    } else {
      state = state.copyWith(
        orders: state.orders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.completed) : o)
            .toList(),
      );
    }
  }

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
      searchRadiusKm: state.searchRadiusKm,
      onboardingSeen: state.onboardingSeen,
    );
    _prefs?.clearUser();
    _prefs?.setRole(UserRole.customer);
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
