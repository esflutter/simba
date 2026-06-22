import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/utils/date_time_formatters.dart' show kPriceMin;
import '../../core/utils/pb_date.dart';
import '../../core/utils/realtime_throttle.dart';
import '../mock/app_state.dart';
import '../models/models.dart';
import 'auth_repository.dart' show purgeLocalUserData;
import 'order_mapper.dart';
import 'pocketbase_client.dart';

/// Все взаимодействия с коллекцией `orders` PocketBase. Если бэкенд
/// не подключён — методы возвращают данные из мок-`AppController`.
class OrdersRepository {
  OrdersRepository(this._pb, this._ref);

  final PocketBase? _pb;
  final Ref _ref;

  bool get _isLive => _pb != null;

  /// Дефолтный таймаут на нативные методы PB SDK (`getFullList`, `getOne`,
  /// `create`, `update`, `delete`). SDK 0.22 не выставляет таймаут на http,
  /// и при флапающем соединении вызов мог висеть бесконечно — UI оставался
  /// в loading-состоянии без шанса выйти. На custom HTTP-роуты
  /// (`/api/orders/feed`) уже стоит свой `.timeout(seconds: 10)` — там
  /// дополнительно оборачивать не нужно.
  static const Duration _pbTimeout = Duration(seconds: 15);

  /// Тонкая обёртка для читаемости: тот же `withPbAuthRetry(_ref, op)`,
  /// но без необходимости таскать `_ref` через каждый вызов.
  Future<T> _withAuthRetry<T>(Future<T> Function() op) =>
      withPbAuthRetry(_ref, op);

  /// Мои заказы (как заказчик + как исполнитель в работе/завершённые).
  Future<List<Order>> myOrders() async {
    if (!_isLive) return _ref.read(appControllerProvider).myOrders;
    final pb = _pb!;
    final auth = pb.authStore.record;
    if (auth == null) return const [];
    final filter = pb.filter(
      // cancelled включён в ветку исполнителя, чтобы отменённый после
      // принятия заказ (авто-отмена по неявке, удаление аккаунта заказчика)
      // не исчезал из его Истории. Активные списки cancelled отсекают на
      // клиенте, так что в «в работе» он не просочится.
      '(customer = {:uid}) || (executor = {:uid} && (status = "accepted" || status = "completed" || status = "cancelled"))',
      {'uid': auth.id},
    );
    final records = await _withAuthRetry(() => pb
        .collection('orders')
        .getFullList(
          filter: filter,
          sort: '-created',
          expand: 'customer,executor,category',
        )
        .timeout(_pbTimeout));
    return records
        .map((r) => orderFromRecord(r, pb))
        .whereType<Order>()
        .toList();
  }

  /// Активные заказы, где я — исполнитель (accepted / awaitingPayment).
  /// Используется в «Мои заказы» для добавления секции исполнителя.
  /// На моках — фильтр по `executorId == 'me'`.
  ///
  /// На бэке хранится только `status = "accepted"`; `awaitingPayment` —
  /// клиентский статус, вычисляется в [orderFromRecord] по факту наличия
  /// `work_done_by_executor_at` без `payment_received_at`.
  Future<List<Order>> myExecutorOrders() async {
    if (!_isLive) {
      return _ref
          .read(appControllerProvider)
          .orders
          .where((o) =>
              o.executorId == 'me' &&
              (o.status == OrderStatus.accepted ||
                  o.status == OrderStatus.awaitingPayment))
          .toList();
    }
    final pb = _pb!;
    final auth = pb.authStore.record;
    if (auth == null) return const [];
    final records = await _withAuthRetry(() => pb
        .collection('orders')
        .getFullList(
          filter: pb.filter(
            'executor = {:uid} && status = "accepted"',
            {'uid': auth.id},
          ),
          sort: '-created',
          expand: 'customer,executor,category',
        )
        .timeout(_pbTimeout));
    return records
        .map((r) => orderFromRecord(r, pb))
        .whereType<Order>()
        .toList();
  }

  /// Лента заказов для исполнителя. Возвращает ВСЕ open-заказы в
  /// выбранном городе. Раньше у запроса были lat/lng/radius_km, но
  /// слайдер «расстояние» в UI так и не появился — клиент всегда слал
  /// дефолтный радиус 5 км вокруг центра города, и заказы из спальных
  /// районов в ленту не попадали. Убрали гео-параметры совсем:
  /// бизнес-правило — «вижу заказы своего города», география города
  /// уже задана через `users.city` + правило listRule на orders.
  Future<List<Order>> feed({
    String? categoryId,
    String? cityId,
  }) async {
    if (!_isLive) {
      // Mock-ветка фильтрует по cityId явно: на моках state.orders сидится
      // с центром текущего города, но после переключения города со старыми
      // заказами в state могут оказаться записи прежнего города — отсекаем.
      return _ref
          .read(appControllerProvider)
          .orders
          // Заказ без города считаем совпадением: сид-заказы создаются без
          // cityId, иначе мок-лента всегда пустая (фильтр по точному городу).
          .where((o) =>
              o.status == OrderStatus.open &&
              (cityId == null ||
                  cityId.isEmpty ||
                  (o.cityId?.isEmpty ?? true) ||
                  o.cityId == cityId))
          .toList();
    }
    final pb = _pb!;
    final body = jsonEncode({
      'category': ?categoryId,
      'city': ?cityId,
    });

    Future<http.Response> doRequest() => sendWithSharedClient(
          (c) => c
              .post(
                Uri.parse('${pb.baseURL}/api/orders/feed'),
                headers: {
                  if (pb.authStore.token.isNotEmpty)
                    'Authorization': 'Bearer ${pb.authStore.token}',
                  'Content-Type': 'application/json',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 10)),
        );

    final http.Response resp;
    try {
      resp = await doRequest();
    } catch (e) {
      // В release не пишем `e` — текст ошибки http может содержать URL
      // с query, который попадает в logcat. Ошибку пробрасываем наверх,
      // чтобы лента показала «нет связи / повторить», а не пустой экран
      // (иначе тост ошибки в pull-to-refresh был недостижим).
      if (kDebugMode) {
        debugPrint('[orders_repository] feed transport error: $e');
      }
      rethrow;
    }
    // Auth-flow: токен мог истечь, бэк отдаёт 401. Сначала пытаемся
    // молча обновить токен через общий single-flight — если параллельно
    // лента/мои заказы уже триггерят refresh, тут ждём его результат.
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      http.Response? retry;
      try {
        await pb.refreshAuthSingleFlight();
        retry = await doRequest();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[orders_repository] feed refresh/retry failed: $e');
        }
      }
      if (retry != null && retry.statusCode == 200) {
        return _parseFeedBody(retry.body, pb);
      }
      // Разлогиниваем ТОЛЬКО если токен реально невалиден (как в общей
      // обёртке withPbAuthRetry). Если refresh прошёл, а повтор упёрся во
      // временный сбой (таймаут, 5xx, 429 от rate-limit, 403 city_mismatch) —
      // сессия валидна, НЕ выкидываем юзера и не чистим кэш: отдаём ошибку
      // наверх, лента покажет «не удалось, повторить».
      if (!pb.authStore.isValid) {
        pb.authStore.clear();
        try {
          _ref.read(appControllerProvider.notifier).logout();
          // Полная локальная очистка — иначе фото/данные прошлого юзера
          // остаются в кэше и провайдерах после принудительного выхода.
          purgeLocalUserData(_ref);
        } catch (_) {}
        return const [];
      }
      throw Exception('feed retry failed (${retry?.statusCode ?? 'network'})');
    }
    if (resp.statusCode != 200) {
      throw Exception('feed http ${resp.statusCode}');
    }
    return _parseFeedBody(resp.body, pb);
  }

  /// Разбор тела ответа /api/orders/feed. Любая ошибка парсинга = пустая
  /// лента (с логом для отладки). Также защищаемся от дубликатов: если
  /// бэк/прокси случайно отдал один заказ дважды (например, при retry на
  /// уровне CDN), второе вхождение игнорируется.
  List<Order> _parseFeedBody(String body, PocketBase pb) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[orders_repository] feed JSON parse failed: $e');
      }
      return const [];
    }
    final items = (decoded is Map && decoded['items'] is List)
        ? (decoded['items'] as List)
        : const [];
    final seen = <String>{};
    final out = <Order>[];
    for (final raw in items) {
      final o = _orderFromFeedItem(raw, pb);
      if (o == null) continue;
      if (!seen.add(o.id)) continue;
      out.add(o);
    }
    return out;
  }

  /// Одна запись заказа.
  Future<Order?> get(String orderId) async {
    if (!_isLive) {
      final s = _ref.read(appControllerProvider);
      for (final o in [...s.myOrders, ...s.orders]) {
        if (o.id == orderId) return o;
      }
      return null;
    }
    try {
      final pb = _pb!;
      final r = await _withAuthRetry(() => pb
          .collection('orders')
          .getOne(
            orderId,
            expand: 'customer,executor,category',
          )
          .timeout(_pbTimeout));
      // orderFromRecord может вернуть null для битых записей без customer.
      return orderFromRecord(r, pb);
    } on ClientException catch (e) {
      // $e от PB содержит тело запроса/ответа — в release не пишем.
      if (kDebugMode) {
        debugPrint('[orders_repository] get($orderId) http ${e.statusCode}');
      }
      // 404 — заказ реально удалён → null (экран покажет «заказ снят»).
      // Остальное (сеть/5xx) пробрасываем, чтобы экран показал «не удалось
      // загрузить» с кнопкой повтора, а не врал «заказ не найден» на живой
      // заказ при плохой сети.
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (e) {
      // Таймаут/обрыв сети — тоже наверх, не маскируем под «не найден».
      if (kDebugMode) {
        debugPrint('[orders_repository] get($orderId) error: $e');
      }
      rethrow;
    }
  }

  /// Создание заказа.
  ///
  /// [clientUid] — клиентский UUID для идемпотентности. Если задан, и
  /// сеть оборвалась после успешной записи на сервере, повторная
  /// отправка с тем же UID не создаст дубликат: сервер вернёт ошибку
  /// уникального индекса, а мы найдём ранее созданный заказ через
  /// фильтр и вернём его как успех.
  Future<Order> create({
    required Order draft,
    List<File>? photoFiles,
    String? clientUid,
  }) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).createOrder(draft);
      return draft;
    }
    final pb = _pb!;
    // authStore.record может быть null даже при isValid токене (после refresh
    // без user-data, после авто-logout по 401). Без явной проверки
    // `record!.id` ниже даёт TypeError — лучше отвалиться раньше с
    // понятной диагностикой, чем тащить запрос с битым customer-id.
    final me = pb.authStore.record;
    if (me == null) {
      throw StateError('Cannot create order: PB authStore.record is null');
    }
    String? normalizedPhone;
    if (draft.forOtherPhone != null && draft.forOtherPhone!.isNotEmpty) {
      final digits = draft.forOtherPhone!.replaceAll(RegExp(r'\D'), '');
      String d = digits;
      if (d.length == 11 && d[0] == '8') d = '7${d.substring(1)}';
      if (d.length == 10) d = '7$d';
      if (d.length == 11 && d[0] == '7') normalizedPhone = '+$d';
    }
    // trim() для title/description — UI-валидация уже работает с
     // тримленным значением (`title.trim().isNotEmpty`), но в БД до
    // этого уходили пробелы по краям. Поиск и сортировка по этим полям
    // ломались, а карточки в ленте выглядели с висящим пробелом.
    final body = <String, dynamic>{
      'customer': me.id,
      'category': draft.categoryId,
      // Сырой id города (как на сервере), не резолвленный через встроенный
      // список с молчаливым фолбэком на Москву.
      'city': _ref.read(appControllerProvider).selectedCityId,
      'title': draft.title.trim(),
      'description': draft.description.trim(),
      'address': draft.address,
      'lat': draft.location.latitude,
      'lng': draft.location.longitude,
      'price_rub': draft.priceRub,
      'status': 'open',
      'payment_method': draft.paymentMethod.dbValue,
      'asap': draft.asap,
      if (draft.scheduledAt != null)
        'scheduled_at': draft.scheduledAt!.toUtc().toIso8601String(),
      'for_other_phone': ?normalizedPhone,
      if (clientUid != null && clientUid.isNotEmpty) 'client_uid': clientUid,
    };
    // Стримим файлы с диска. До этого был `readAsBytes()` + fromBytes —
    // он загружал все фото в heap одновременно: 3 × 8 МБ = 24 МБ RAM,
    // OOM на дешёвых Android (1–2 ГБ). MultipartFile.fromPath сам
    // открывает файл и читает его кусочками во время отправки, не
    // загружая целиком в память. Размер указываем явно — http package
    // ставит правильный Content-Length вместо chunked transfer.
    //
    // ВАЖНО: список файлов пересобираем на КАЖДУЮ попытку. Поток
    // `f.openRead()` одноразовый, а `_withAuthRetry` при истёкшем токене
    // (401/403 — типично после возврата из фона) обновляет токен и
    // повторяет операцию целиком. Если переиспользовать уже прочитанные
    // потоки, повтор детерминированно падает («поток уже прослушан»), и
    // создание заказа С ФОТО не проходит — пользователю приходится жать
    // «Опубликовать» заново. Замыкание открывает свежие потоки на каждый
    // вызов.
    Future<List<http.MultipartFile>> buildFiles() async {
      final List<http.MultipartFile> files = [];
      for (final f in photoFiles ?? const <File>[]) {
        if (!f.existsSync()) continue;
        final length = await f.length();
        files.add(http.MultipartFile(
          'photos',
          f.openRead(),
          length,
          filename: f.path.split(Platform.pathSeparator).last,
        ));
      }
      return files;
    }
    // Перед публикацией синхронизируем серверный users.city с городом
    // заказа. Смена города отправляется «вслепую» (fire-and-forget PATCH) и
    // могла не дойти при обрыве сети — тогда серверный city остаётся старым,
    // и create упирается в city_mismatch. Идемпотентная правка (тот же
    // город) гарантирует совпадение и убирает тупик «сменил город → создаю».
    final cityForOrder = _ref.read(appControllerProvider).selectedCityId;
    if (cityForOrder != null && cityForOrder.isNotEmpty) {
      try {
        await _withAuthRetry(() => pb
            .collection('users')
            .update(me.id, body: {'city': cityForOrder})
            .timeout(_pbTimeout));
      } catch (_) {
        // Сеть недоступна — сам create ниже вернёт понятную ошибку сети.
      }
    }
    try {
      // upload фото может быть тяжелее обычного create — даём чуть больше
      // времени (фото на 8 МБ лимите × 5 шт + multipart-обвязка).
      final r = await _withAuthRetry(() async {
        final files = await buildFiles();
        return pb
            .collection('orders')
            .create(body: body, files: files)
            .timeout(const Duration(seconds: 30));
      });
      final created = orderFromRecord(r, pb);
      if (created == null) {
        // Не должно случиться: мы только что передали `customer` в body
        // и получили запись назад. Если бэк всё же вернул битую — это
        // редкая аномалия, лучше упасть, чем тихо потерять заказ.
        throw StateError('orderFromRecord returned null for just-created order ${r.id}');
      }
      return created;
    } catch (e) {
      // Если был передан client_uid — проверим, не лежит ли уже такой
      // заказ на сервере. Это покрывает три сценария:
      //   1. Таймаут / обрыв сети после успешной отправки тела.
      //   2. ACK потерялся, юзер тапнул «Опубликовать» ещё раз — здесь
      //      сервер вернёт constraint violation на уникальном индексе.
      //   3. Любая другая 4xx, при которой запись фактически создалась.
      // Если запись находится — операция идемпотентно успешна.
      if (clientUid != null && clientUid.isNotEmpty) {
        try {
          final existing = await pb
              .collection('orders')
              .getFirstListItem(
                pb.filter(
                  'customer = {:c} && client_uid = {:u}',
                  {'c': me.id, 'u': clientUid},
                ),
                expand: 'customer,executor,category',
              )
              .timeout(const Duration(seconds: 10));
          final order = orderFromRecord(existing, pb);
          if (order != null) return order;
        } catch (_) {/* записи нет — пробрасываем исходную ошибку */}
      }
      rethrow;
    }
  }

  /// Отмена заказа заказчиком = полное удаление записи.
  ///
  /// По ТЗ-схеме «Заказчик может отказаться → Заказ исчезает» — без
  /// различия между `open` (до accept) и `accepted` (после accept,
  /// пока время не наступило и стороны ещё не отметились).
  /// Клиентский UI скрывает кнопку «Отменить заказ» вне этого окна
  /// (см. `Order.canCancelByCustomer()`).
  ///
  /// Бэк-правило согласовано с этим окном: миграция 027 расширила
  /// `orders.deleteRule` и `onRecordDelete`-хук в pb_hooks/main.pb.js
  /// так, что DELETE проходит и для `accepted`-заказа, пока:
  ///   - ни одна из 3 FSM-дат не выставлена;
  ///   - время заказа ещё не наступило (или ASAP без даты).
  /// На моках то же самое реализовано в `AppController.cancelOrder`.
  Future<void> cancel(String orderId) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).cancelOrder(orderId);
      return;
    }
    try {
      await _withAuthRetry(() =>
          _pb!.collection('orders').delete(orderId).timeout(_pbTimeout));
    } on ClientException catch (e) {
      // 404 = заказ уже удалён (фоновой задачей 30-дневной чистки, либо
      // параллельным запросом с другого устройства). Для пользователя это
      // успех: цель «убрать заказ» уже достигнута. Прокидывать ошибку
      // наверх не нужно — UI покажет «не удалось», хотя по факту всё ок.
      if (e.statusCode == 404) return;
      rethrow;
    }
  }

  /// Исполнитель отказывается от принятого заказа — заказ возвращается
  /// в ленту (`status = open`, `executor = null`, остальные pending-отклики
  /// восстанавливаются хуком на сервере). Доступно только пока:
  ///   - есть `scheduled_at` И он ещё не наступил;
  ///   - исполнитель ещё не отметил «работа выполнена».
  /// Бэк-валидация FSM (см. main.pb.js) повторно проверяет эти условия — UI
  /// просто прячет кнопку для других случаев. Любая ошибка пробрасывается
  /// наверх, чтобы UI показал тост.
  Future<void> cancelAsExecutor(String orderId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .releaseOrderAsExecutor(orderId);
      return;
    }
    try {
      await _withAuthRetry(() => _pb!
          .collection('orders')
          .update(orderId, body: {'status': 'open'})
          .timeout(_pbTimeout));
    } on ClientException catch (e) {
      // 404 — заказ удалён (заказчик отменил параллельно или сработала
      // 30-дневная чистка). Для исполнителя «отказаться» уже состоялось.
      if (e.statusCode == 404) return;
      rethrow;
    }
  }

  /// Заказчик отмечает «работа выполнена».
  ///
  /// В новой схеме (без `awaitingPayment`) заказчик и исполнитель работают
  /// в двух независимых флоу: каждый отмечает свою часть и оставляет отзыв.
  /// Раньше клиент пытался ОПТИМИСТИЧНО проставить и
  /// `work_done_by_executor_at` для того, чтобы серверный hook сразу мог
  /// сложить три даты и перевести в completed. Но это поле принадлежит
  /// исполнителю — сервер отдаёт 400 «only_executor_can_mark_work_done»
  /// (см. main.pb.js строка ~1099). Заказчик ставит только свою дату;
  /// финальное «оба отметились» докрутит исполнитель, либо крон
  /// auto-confirm-completed через 48 часов.
  Future<void> confirmWork(Order order) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .markCustomerCompleted(order.id);
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final body = <String, dynamic>{
      'work_confirmed_by_customer_at': now,
    };
    try {
      await _withAuthRetry(() => _pb!
          .collection('orders')
          .update(order.id, body: body)
          .timeout(_pbTimeout));
    } on ClientException catch (e) {
      // 404 — заказ удалён (отменили параллельно, или 30-дневная чистка).
      if (e.statusCode == 404) return;
      rethrow;
    }
  }

  /// Исполнитель отмечает «оплата получена».
  ///
  /// Исполнителю разрешено ставить и `work_done_by_executor_at`, и
  /// `payment_received_at`. Если первое ещё не выставлено (бывает, если
  /// executor пропустил отдельную отметку «работа выполнена» и сразу
  /// тапает «оплата получена») — заполняем оба, чтобы серверный hook
  /// корректно сложил три даты и перевёл заказ в `completed`.
  Future<void> confirmPaymentReceived(Order order) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .markExecutorCompleted(order.id);
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final body = <String, dynamic>{
      'payment_received_at': now,
      if (order.workDoneAt == null) 'work_done_by_executor_at': now,
    };
    try {
      await _withAuthRetry(() => _pb!
          .collection('orders')
          .update(order.id, body: body)
          .timeout(_pbTimeout));
    } on ClientException catch (e) {
      // 404 — заказ удалён (заказчик отменил параллельно, или сработала
      // 30-дневная чистка). Считаем действие выполненным — отметка
      // больше не нужна, заказа нет.
      if (e.statusCode == 404) return;
      rethrow;
    }
  }


  Order? _orderFromFeedItem(dynamic raw, PocketBase pb) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    try {
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lng = (m['lng'] as num?)?.toDouble() ?? 0;
      // (0,0) — заведомо битая запись. Лента/карта показали бы маркер
      // в Гвинейском заливе, что хуже чем «заказ не отобразился вообще».
      // Реальный заказ из РФ имеет lat≈41..82 и lng≈19..170 — нулевые
      // координаты сюда не попадают по бизнесу.
      if (lat == 0 && lng == 0) {
        if (kDebugMode) {
          debugPrint('[orders_repository] feed item ${m['id']} has 0/0 coords — skipping');
        }
        return null;
      }
      final id = m['id'] as String;
      // Бэк-роут `/api/orders/feed` возвращает массив имён файлов в поле
      // `photos`, но без collectionId. Собираем canonical-URL через helper
      // `pbFileUrl` — он работает для НЕ-protected файлов; protected потребует
      // token-параметр через `pb.files.getUrl(record, name)` и реальный record.
      // `orders.photos` сейчас НЕ protected (см. миграцию 003) — этого достаточно.
      // whereType — устойчиво к битым записям, где в массиве photos
      // оказалось null/число. Иначе cast<String> ленив и роняет
      // парсинг всего фид-ответа на первой битой записи.
      final photoNames =
          (m['photos'] as List?)?.whereType<String>() ?? const <String>[];
      final photoUrls = photoNames
          .map((name) => pbFileUrl(
                pb,
                collection: 'orders',
                recordId: id,
                filename: name,
              ))
          .toList(growable: false);
      // Поля customer/executor/payment_method опциональны в ответе
      // `/api/orders/feed` (зависит от версии бэка). Если бэк их прокинул —
      // используем; иначе остаётся дефолт. Заказчику/исполнителю обычно
      // достаточно полей карточки в ленте; полная запись подтянется через
      // `OrdersRepository.get()` при открытии деталей.
      final customerIdRaw = m['customer']?.toString();
      final executorIdRaw = m['executor']?.toString();
      final paymentRaw = m['payment_method']?.toString();
      final cityRaw = m['city']?.toString();
      // Имя и имя файла фото заказчика — отдаются бэк-эндпоинтом
      // /api/orders/feed inline. Без них клиент рисовал «Пользователь»
      // в карточке заказа до первого открытия деталей (там подтягивает
      // expand=customer). См. соответствующее место в pb_hooks/main.pb.js.
      final customerNameRaw = m['customer_name']?.toString();
      final customerPhotoRaw = m['customer_photo']?.toString();
      // Без customer теряется логика «свой/чужой заказ» (см. order_mapper).
      // Пропускаем такую запись — выше она отфильтруется через whereType.
      if (customerIdRaw == null || customerIdRaw.isEmpty) {
        return null;
      }
      final customerPhotoUrl =
          (customerPhotoRaw != null && customerPhotoRaw.isNotEmpty)
              ? pbFileUrl(
                  pb,
                  collection: 'users',
                  recordId: customerIdRaw,
                  filename: customerPhotoRaw,
                )
              : null;
      // Битая `created` → пропускаем запись целиком. Раньше fallback на
      // DateTime.now() выглядел как «только что создан» — сортировка ленты
      // ставила такие заказы наверх, искажая порядок.
      final createdAt = parsePbDate(m['created']?.toString());
      if (createdAt == null) {
        if (kDebugMode) {
          debugPrint('[orders_repository] feed item ${m['id']} has invalid `created` — skipping');
        }
        return null;
      }
      // priceRub меньше kPriceMin валидно невозможен — это сигнал что
      // бэк прислал битую запись, лучше не показывать чем «бесплатный заказ».
      final price = (m['price_rub'] as num?)?.toInt() ?? 0;
      if (price < kPriceMin) {
        if (kDebugMode) {
          debugPrint('[orders_repository] feed item ${m['id']} has invalid price_rub=$price — skipping');
        }
        return null;
      }
      return Order(
        id: id,
        customerId: customerIdRaw,
        categoryId: m['category']?.toString() ?? '',
        cityId: (cityRaw == null || cityRaw.isEmpty) ? null : cityRaw,
        title: m['title']?.toString() ?? '',
        description: '',
        address: m['address']?.toString() ?? '',
        location: LatLng(lat, lng),
        priceRub: price,
        status: OrderStatus.open,
        createdAt: createdAt,
        // Свежесть в ленте считается от relisted_at (заказ приняли и вернули
        // в работу), иначе от created — как и серверная чистка старых заказов.
        // Без этого давно созданный, но недавно вернувшийся заказ старше 60
        // дней пропадал из ленты. Сервер отдаёт relisted_at в ответе фида.
        relistedAt: parsePbDate(m['relisted_at']?.toString()),
        scheduledAt: parsePbDate(m['scheduled_at']?.toString()),
        asap: m['asap'] == true,
        executorId: (executorIdRaw == null || executorIdRaw.isEmpty)
            ? null
            : executorIdRaw,
        paymentMethod: PaymentMethodMapping.fromDbValue(paymentRaw),
        photoPaths: photoUrls,
        customerName:
            (customerNameRaw != null && customerNameRaw.isNotEmpty)
                ? customerNameRaw
                : null,
        customerPhotoUrl: customerPhotoUrl,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[orders_repository] failed to parse feed item: $e');
      }
      return null;
    }
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.read(pocketbaseProvider), ref);
});

/// Стрим «мои заказы» — переподписывается при изменении auth.
final myOrdersStreamProvider = FutureProvider<List<Order>>((ref) async {
  return ref.read(ordersRepositoryProvider).myOrders();
});

/// Активные заказы, где я — исполнитель. Для секции в «Мои заказы»,
/// когда PB подключён. На моках — пустой список (UI всё равно соберёт
/// эти заказы из `state.orders` сам).
final myExecutorOrdersProvider = FutureProvider<List<Order>>((ref) async {
  return ref.read(ordersRepositoryProvider).myExecutorOrders();
});

/// Лента заказов для текущего города/радиуса. Используется feed/search.
/// На моках возвращает открытые заказы из `state.orders`.
///
/// ВАЖНО: используем `select`, чтобы провайдер пересоздавался ТОЛЬКО при
/// смене города или радиуса. Иначе любая мутация AppState (createOrder,
/// addReview, setRole, executorActive, …) триггерила бы новый HTTP-запрос
/// в `/api/orders/feed` — HTTP-флуд и дёрганая лента.
final feedOrdersProvider = FutureProvider<List<Order>>((ref) async {
  // Сырой сохранённый id города (как пришёл с сервера), НЕ резолвленный
  // через встроенный список (тот при незнакомом id молча подставляет
  // Москву). Иначе у жителя города вне встроенных 16 клиент слал бы чужой
  // город → 403 и полностью сломанные лента/создание без релиза.
  final cityId = ref.watch(
    appControllerProvider.select((s) => s.selectedCityId),
  );
  // Лента — это все open-заказы города. Никаких радиусов больше нет:
  // в UI слайдера «расстояние» не было, дефолтный 5-км круг скрывал
  // заказы из спальных районов. Бизнес-правило простое — видим то,
  // что в моём городе.
  return ref.read(ordersRepositoryProvider).feed(cityId: cityId);
});

/// Единая на всё приложение realtime-подписка на изменения заказов.
/// Раньше лента и «Мои заказы» держали по своей подписке на orders/* — и
/// каждое событие обрабатывалось дважды, плюс на off-stage вкладках висели
/// лишние слушатели. Теперь один слушатель на сессию обновляет все три
/// списка заказов сразу: статусы приходят на любой вкладке, без дублей.
/// Главный экран watch'ит его, пока пользователь залогинен; при выходе
/// (экран демонтируется) подписка снимается, при входе — поднимается снова.
final ordersRealtimeProvider = Provider.autoDispose<void>((ref) {
  final pb = ref.watch(pocketbaseProvider);
  // Пересоздаём подписку при смене юзера (гость→вошёл, выход). Без этого SDK
  // не переавторизует уже открытую анонимную подписку: гость подписался бы
  // без токена, и после входа realtime молчал бы весь сеанс. Гостю
  // (userId == null) подписка не нужна — события заказов ему по правилам
  // коллекции всё равно не приходят; при входе провайдер пересоздастся
  // (userId сменится) и подпишется уже с токеном.
  final userId = ref.watch(appControllerProvider.select((s) => s.user?.id));
  if (pb == null || userId == null) return;
  final throttle = RealtimeThrottle();
  var disposed = false;
  Future<void> Function()? unsub;

  Future<void> start() async {
    try {
      final u = await pb.collection('orders').subscribe('*', (_) {
        if (disposed) return;
        // Первое событие применяем сразу (статус заказа меняется в реальном
        // времени), всплеск последующих чужих событий склеиваем.
        throttle.run(() {
          if (disposed) return;
          ref.invalidate(feedOrdersProvider);
          ref.invalidate(myOrdersStreamProvider);
          ref.invalidate(myExecutorOrdersProvider);
        });
      });
      if (disposed) {
        await u();
        return;
      }
      unsub = u;
    } catch (_) {/* WebSocket недоступен — экраны работают без realtime */}
  }

  // ignore: discarded_futures
  start();

  ref.onDispose(() {
    disposed = true;
    throttle.dispose();
    final u = unsub;
    unsub = null;
    if (u != null) {
      // ignore: discarded_futures
      u();
    }
  });
});
