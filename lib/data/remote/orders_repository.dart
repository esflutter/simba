import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

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
    final records = await pb.collection('orders').getFullList(
          filter: filter,
          sort: '-created',
          expand: 'customer,executor,category',
        );
    return records.map((r) => orderFromRecord(r, pb)).toList();
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
    final records = await pb.collection('orders').getFullList(
          filter: pb.filter(
            'executor = {:uid} && status = "accepted"',
            {'uid': auth.id},
          ),
          sort: '-created',
          expand: 'customer,executor,category',
        );
    return records.map((r) => orderFromRecord(r, pb)).toList();
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
    } catch (_) {
      return const [];
    }
    // Auth-flow: токен мог истечь, бэк отдаёт 401. Чистим pb.authStore +
    // мок-AppController, чтобы redirect-guard в роутере отправил на /auth/phone
    // при следующей навигации (см. `_buildRouter.redirect`).
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      pb.authStore.clear();
      try {
        _ref.read(appControllerProvider.notifier).logout();
      } catch (_) {}
      return const [];
    }
    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.body);
    final items = (body is Map && body['items'] is List)
        ? (body['items'] as List)
        : const [];
    return items
        .map<Order?>((it) => _orderFromFeedItem(it, pb))
        .whereType<Order>()
        .toList();
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
      final r = await pb.collection('orders').getOne(
            orderId,
            expand: 'customer,executor,category',
          );
      return orderFromRecord(r, pb);
    } catch (_) {
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
    String? normalizedPhone;
    if (draft.forOtherPhone != null && draft.forOtherPhone!.isNotEmpty) {
      final digits = draft.forOtherPhone!.replaceAll(RegExp(r'\D'), '');
      String d = digits;
      if (d.length == 11 && d[0] == '8') d = '7${d.substring(1)}';
      if (d.length == 10) d = '7$d';
      if (d.length == 11 && d[0] == '7') normalizedPhone = '+$d';
    }
    final body = <String, dynamic>{
      'customer': pb.authStore.record!.id,
      'category': draft.categoryId,
      'city': _ref.read(appControllerProvider).selectedCity.id,
      'title': draft.title,
      'description': draft.description,
      'address': draft.address,
      'lat': draft.location.latitude,
      'lng': draft.location.longitude,
      'price_kopecks': draft.priceRub * 100,
      'status': 'open',
      // В SimbA в `PaymentMethod` сейчас только `cash`. Не хардкодим, а
      // мапим из draft.paymentMethod: когда enum расширится (cashless и т.п.),
      // правка останется в одном месте — `_paymentMethodToString`.
      'payment_method': _paymentMethodToString(draft.paymentMethod),
      'asap': draft.asap,
      if (draft.scheduledAt != null)
        'scheduled_at': draft.scheduledAt!.toUtc().toIso8601String(),
      'for_other_phone': ?normalizedPhone,
    };
    // Асинхронное чтение байтов, чтобы не блокировать UI-isolate на
    // больших фото. fromBytes требует уже готовый буфер — поэтому
    // последовательный await readAsBytes (а не fromPath/Stream — там
    // нужны Length-заголовки на сервере).
    final List<http.MultipartFile> files = [];
    for (final f in photoFiles ?? const <File>[]) {
      final bytes = await f.readAsBytes();
      files.add(http.MultipartFile.fromBytes(
        'photos',
        bytes,
        filename: f.path.split(Platform.pathSeparator).last,
      ));
    }
    final r = await pb.collection('orders').create(body: body, files: files);
    return orderFromRecord(r, pb);
  }

  /// Отмена заказа заказчиком. До accept — DELETE, после accept — PATCH
  /// `status: cancelled` (DELETE на accepted даст 403 из-за API-rules).
  ///
  /// Чтобы не было race condition «getOne → между ним и DELETE заказ
  /// принят исполнителем», сначала пробуем DELETE: PB вернёт 403/404,
  /// если заказ уже не в `open`-состоянии — тогда переключаемся на PATCH.
  Future<void> cancel(String orderId) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).cancelOrder(orderId);
      return;
    }
    final pb = _pb!;
    final coll = pb.collection('orders');
    try {
      await coll.delete(orderId);
    } on ClientException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 404) {
        await coll.update(orderId, body: {
          'status': 'cancelled',
          'cancel_reason': 'by_customer',
          'cancelled_by': pb.authStore.record?.id,
        });
      } else {
        rethrow;
      }
    }
  }

  /// Исполнитель отмечает «работа выполнена».
  Future<void> markWorkDone(String orderId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .markWorkDone(orderId, inMyOrders: false);
      return;
    }
    await _pb!.collection('orders').update(orderId, body: {
      'work_done_by_executor_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Заказчик подтверждает работу (= передал наличные).
  Future<void> confirmWork(String orderId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .confirmPayment(orderId, inMyOrders: true);
      return;
    }
    await _pb!.collection('orders').update(orderId, body: {
      'work_confirmed_by_customer_at':
          DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Исполнитель подтверждает получение оплаты — финальный шаг.
  Future<void> confirmPaymentReceived(String orderId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .confirmPayment(orderId, inMyOrders: false);
      return;
    }
    await _pb!.collection('orders').update(orderId, body: {
      'payment_received_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Обратное преобразование [PaymentMethod] → строка для БД.
  /// При расширении enum (cashless, card, etc.) — расширь switch.
  String _paymentMethodToString(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'cash';
    }
  }

  Order? _orderFromFeedItem(dynamic raw, PocketBase pb) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    try {
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lng = (m['lng'] as num?)?.toDouble() ?? 0;
      final id = m['id'] as String;
      // Бэк-роут `/api/orders/feed` возвращает массив имён файлов в поле
      // `photos`, но без collectionId/collectionName — `pb.files.getUrl`
      // ожидает RecordModel. Cинтезируем минимальный RecordModel из id и
      // имени коллекции, чтобы SDK сам собрал URL через canonical путь.
      // Если `photos` помечено protected: true — pb.files.getUrl добавит
      // token-параметр, наш ручной шаблон сломался бы.
      final photoNames = (m['photos'] as List?)?.cast<String>() ?? const [];
      final fakeRecord = RecordModel({
        'id': id,
        'collectionId': 'orders',
        'collectionName': 'orders',
      });
      final photoUrls = photoNames
          .map((name) => pb.files.getUrl(fakeRecord, name).toString())
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
      return Order(
        id: id,
        customerId: (customerIdRaw == null || customerIdRaw.isEmpty)
            ? ''
            : customerIdRaw,
        categoryId: m['category']?.toString() ?? '',
        cityId: (cityRaw == null || cityRaw.isEmpty) ? null : cityRaw,
        title: m['title']?.toString() ?? '',
        description: '',
        address: m['address']?.toString() ?? '',
        location: LatLng(lat, lng),
        // Округление до рубля идентично `order_mapper.dart` для полной
        // записи — иначе цены в ленте и деталях заказа могли бы
        // расходиться на 1 рубль при kopecks не кратном 100.
        priceRub:
            (((m['price_kopecks'] as num?)?.toDouble() ?? 0) / 100).round(),
        status: OrderStatus.open,
        createdAt:
            DateTime.tryParse(m['created']?.toString() ?? '') ?? DateTime.now(),
        scheduledAt: m['scheduled_at'] == null
            ? null
            : DateTime.tryParse(m['scheduled_at'].toString()),
        asap: m['asap'] == true,
        executorId: (executorIdRaw == null || executorIdRaw.isEmpty)
            ? null
            : executorIdRaw,
        paymentMethod: paymentRaw == 'cash'
            ? PaymentMethod.cash
            : PaymentMethod.cash,
        photoPaths: photoUrls,
      );
    } catch (_) {
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
