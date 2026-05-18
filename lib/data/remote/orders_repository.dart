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
import '../mock/app_state.dart';
import '../models/models.dart';
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
      '(customer = {:uid}) || (executor = {:uid} && (status = "accepted" || status = "completed"))',
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

  /// Лента заказов для исполнителя (гео-поиск через кастомный роут).
  Future<List<Order>> feed({
    required double lat,
    required double lng,
    required double radiusKm,
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
          .where((o) => o.status == OrderStatus.open && (cityId == null || cityId.isEmpty || o.cityId == cityId))
          .toList();
    }
    final pb = _pb!;
    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('${pb.baseURL}/api/orders/feed'),
            headers: {
              if (pb.authStore.token.isNotEmpty)
                'Authorization': 'Bearer ${pb.authStore.token}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'lat': lat,
              'lng': lng,
              'radius_km': radiusKm,
              'category': ?categoryId,
              'city': ?cityId,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[orders_repository] feed transport error: $e');
      return const [];
    }
    // Auth-flow: токен мог истечь, бэк отдаёт 401. Сначала пытаемся
    // молча обновить токен через authRefresh — это снимает раздражающий
    // вылет на /auth/phone посреди сессии, если token истёк по TTL.
    // Если refresh не помог — чистим и кидаем юзера на логин.
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      try {
        await pb.collection('users').authRefresh().timeout(_pbTimeout);
        // Повтор запроса с новым токеном. Сохраняем cap на 1 — больше двух
        // авторизационных циклов подряд почти всегда означает реальную
        // проблему авторизации, продолжать перебор нет смысла.
        final retry = await http
            .post(
              Uri.parse('${pb.baseURL}/api/orders/feed'),
              headers: {
                if (pb.authStore.token.isNotEmpty)
                  'Authorization': 'Bearer ${pb.authStore.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'lat': lat,
                'lng': lng,
                'radius_km': radiusKm,
                'category': ?categoryId,
                'city': ?cityId,
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (retry.statusCode == 200) {
          return _parseFeedBody(retry.body, pb);
        }
      } catch (e) {
        // refresh упал — токен реально просрочен/отозван
        debugPrint('[orders_repository] feed authRefresh failed: $e');
      }
      pb.authStore.clear();
      try {
        _ref.read(appControllerProvider.notifier).logout();
      } catch (_) {}
      return const [];
    }
    if (resp.statusCode != 200) return const [];
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
      debugPrint('[orders_repository] feed JSON parse failed: $e');
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
    } catch (e) {
      debugPrint('[orders_repository] get($orderId) failed: $e');
      return null;
    }
  }

  /// Создание заказа.
  Future<Order> create({
    required Order draft,
    List<File>? photoFiles,
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
    final body = <String, dynamic>{
      'customer': me.id,
      'category': draft.categoryId,
      'city': _ref.read(appControllerProvider).selectedCity.id,
      'title': draft.title,
      'description': draft.description,
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
    };
    // Стримим файлы с диска. До этого был `readAsBytes()` + fromBytes —
    // он загружал все фото в heap одновременно: 3 × 8 МБ = 24 МБ RAM,
    // OOM на дешёвых Android (1–2 ГБ). MultipartFile.fromPath сам
    // открывает файл и читает его кусочками во время отправки, не
    // загружая целиком в память. Размер указываем явно — http package
    // ставит правильный Content-Length вместо chunked transfer.
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
    // upload фото может быть тяжелее обычного create — даём чуть больше
    // времени (фото на 8 МБ лимите × 5 шт + multipart-обвязка).
    final r = await _withAuthRetry(() => pb
        .collection('orders')
        .create(body: body, files: files)
        .timeout(const Duration(seconds: 30)));
    final created = orderFromRecord(r, pb);
    if (created == null) {
      // Не должно случиться: мы только что передали `customer` в body
      // и получили запись назад. Если бэк всё же вернул битую — это
      // редкая аномалия, лучше упасть, чем тихо потерять заказ.
      throw StateError('orderFromRecord returned null for just-created order ${r.id}');
    }
    return created;
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
        debugPrint('[orders_repository] feed item ${m['id']} has 0/0 coords — skipping');
        return null;
      }
      final id = m['id'] as String;
      // Бэк-роут `/api/orders/feed` возвращает массив имён файлов в поле
      // `photos`, но без collectionId. Собираем canonical-URL через helper
      // `pbFileUrl` — он работает для НЕ-protected файлов; protected потребует
      // token-параметр через `pb.files.getUrl(record, name)` и реальный record.
      // `orders.photos` сейчас НЕ protected (см. миграцию 003) — этого достаточно.
      final photoNames = (m['photos'] as List?)?.cast<String>() ?? const [];
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
        debugPrint('[orders_repository] feed item ${m['id']} has invalid `created` — skipping');
        return null;
      }
      // priceRub меньше kPriceMin валидно невозможен — это сигнал что
      // бэк прислал битую запись, лучше не показывать чем «бесплатный заказ».
      final price = (m['price_rub'] as num?)?.toInt() ?? 0;
      if (price < kPriceMin) {
        debugPrint('[orders_repository] feed item ${m['id']} has invalid price_rub=$price — skipping');
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
      debugPrint('[orders_repository] failed to parse feed item: $e');
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
  final city =
      ref.watch(appControllerProvider.select((s) => s.selectedCity));
  final radiusKm =
      ref.watch(appControllerProvider.select((s) => s.searchRadiusKm));
  // Передаём cityId — бэк фильтрует ленту строго по городу пользователя
  // (city == auth.user.city на бэке). Лента НЕ должна показывать заказы
  // из чужих городов: бизнес-правило SimbA — юзер видит только свой город.
  return ref.read(ordersRepositoryProvider).feed(
        lat: city.center.latitude,
        lng: city.center.longitude,
        radiusKm: radiusKm,
        cityId: city.id,
      );
});
