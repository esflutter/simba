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
    final filter =
        '(customer = "${auth.id}") || (executor = "${auth.id}" && (status = "accepted" || status = "completed"))';
    final records = await pb.collection('orders').getFullList(
          filter: filter,
          sort: '-created',
        );
    return records.map((r) => orderFromRecord(r, pb)).toList();
  }

  /// Активные заказы, где я — исполнитель (accepted / awaitingPayment).
  /// Используется в «Мои заказы» для добавления секции исполнителя.
  /// На моках — фильтр по `executorId == 'me'`.
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
          filter:
              'executor = "${auth.id}" && (status = "accepted" || status = "awaiting_payment")',
          sort: '-created',
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
      return _ref
          .read(appControllerProvider)
          .orders
          .where((o) => o.status == OrderStatus.open)
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
    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.body);
    final items = (body is Map && body['items'] is List)
        ? (body['items'] as List)
        : const [];
    return items
        .map<Order?>((it) => _orderFromFeedItem(it))
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
      final r = await pb.collection('orders').getOne(orderId);
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
      'payment_method': 'cash',
      'asap': draft.asap,
      if (draft.scheduledAt != null)
        'scheduled_at': draft.scheduledAt!.toUtc().toIso8601String(),
      'for_other_phone': ?normalizedPhone,
    };
    final files = (photoFiles ?? const <File>[])
        .map((f) => http.MultipartFile.fromBytes(
              'photos',
              f.readAsBytesSync(),
              filename: f.path.split(Platform.pathSeparator).last,
            ))
        .toList();
    final r = await pb.collection('orders').create(body: body, files: files);
    return orderFromRecord(r, pb);
  }

  /// Отмена заказа заказчиком. До accept — DELETE, после accept — PATCH
  /// `status: cancelled` (DELETE на accepted даст 403 из-за API-rules).
  Future<void> cancel(String orderId) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).cancelOrder(orderId);
      return;
    }
    final pb = _pb!;
    final coll = pb.collection('orders');
    try {
      final r = await coll.getOne(orderId);
      final status = r.getStringValue('status');
      if (status == 'accepted') {
        await coll.update(orderId, body: {
          'status': 'cancelled',
          'cancel_reason': 'by_customer',
        });
        return;
      }
    } catch (_) {
      // если не смогли прочитать — попробуем DELETE, ниже
    }
    await coll.delete(orderId);
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

  Order? _orderFromFeedItem(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    try {
      final lat = (m['lat'] as num?)?.toDouble() ?? 0;
      final lng = (m['lng'] as num?)?.toDouble() ?? 0;
      return Order(
        id: m['id'] as String,
        customerId: '', // в фид-ответе не возвращаем
        categoryId: m['category']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        description: '',
        address: m['address']?.toString() ?? '',
        location: LatLng(lat, lng),
        priceRub: ((m['price_kopecks'] as num?)?.toInt() ?? 0) ~/ 100,
        status: OrderStatus.open,
        createdAt:
            DateTime.tryParse(m['created']?.toString() ?? '') ?? DateTime.now(),
        scheduledAt: m['scheduled_at'] == null
            ? null
            : DateTime.tryParse(m['scheduled_at'].toString()),
        asap: m['asap'] == true,
        photoPaths: (m['photos'] as List?)?.cast<String>() ?? const [],
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
final feedOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final state = ref.watch(appControllerProvider);
  final city = state.selectedCity;
  return ref.read(ordersRepositoryProvider).feed(
        lat: city.center.latitude,
        lng: city.center.longitude,
        radiusKm: state.searchRadiusKm,
      );
});
