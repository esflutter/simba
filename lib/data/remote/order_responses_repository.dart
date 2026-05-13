import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../mock/app_state.dart';
import 'pocketbase_client.dart';

/// CRUD для коллекции `order_responses`.
class OrderResponsesRepository {
  OrderResponsesRepository(this._pb, this._ref);

  final PocketBase? _pb;
  final Ref _ref;

  bool get _isLive => _pb != null;

  /// Список id исполнителей, у которых есть pending-отклик на этот заказ.
  /// На моках берём поле `responses` напрямую из Order.
  Future<List<String>> pendingExecutorIds(String orderId) async {
    if (!_isLive) {
      final s = _ref.read(appControllerProvider);
      for (final o in s.myOrders) {
        if (o.id == orderId) return o.responses;
      }
      for (final o in s.orders) {
        if (o.id == orderId) return o.responses;
      }
      return const [];
    }
    final pb = _pb!;
    final records = await pb.collection('order_responses').getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && status = "pending"',
            {'oid': orderId},
          ),
          sort: 'created',
        );
    return records.map((r) => r.getStringValue('executor')).toList();
  }

  /// Исполнитель откликается на заказ.
  Future<void> respond(String orderId, {int? etaMin, String? comment}) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).takeOrderAsExecutor(orderId);
      return;
    }
    final pb = _pb!;
    final me = pb.authStore.record;
    if (me == null) return;
    await pb.collection('order_responses').create(body: {
      'order_ref': orderId,
      'executor': me.id,
      'status': 'pending',
      'eta_min': ?etaMin,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
  }

  /// Заказчик принимает отклик одного из исполнителей.
  /// Хук на сервере каскадно обновит orders + автодеклайн остальных.
  Future<void> accept(String orderId, String executorId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .acceptResponse(orderId, executorId);
      return;
    }
    final pb = _pb!;
    final list = await pb.collection('order_responses').getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && executor = {:eid} && status = "pending"',
            {'oid': orderId, 'eid': executorId},
          ),
        );
    if (list.isEmpty) return;
    await pb
        .collection('order_responses')
        .update(list.first.id, body: {'status': 'accepted'});
  }

  /// Заказчик отклоняет один отклик.
  Future<void> decline(String orderId, String executorId) async {
    if (!_isLive) {
      _ref
          .read(appControllerProvider.notifier)
          .declineResponse(orderId, executorId);
      return;
    }
    final pb = _pb!;
    final list = await pb.collection('order_responses').getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && executor = {:eid} && status = "pending"',
            {'oid': orderId, 'eid': executorId},
          ),
        );
    if (list.isEmpty) return;
    await pb.collection('order_responses').update(list.first.id, body: {
      'status': 'declined',
      'decline_reason': 'by_customer',
    });
  }
}

final orderResponsesRepositoryProvider =
    Provider<OrderResponsesRepository>((ref) {
  return OrderResponsesRepository(ref.read(pocketbaseProvider), ref);
});
