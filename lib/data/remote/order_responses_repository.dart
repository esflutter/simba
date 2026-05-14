import 'dart:async';

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

  /// Таймаут на нативные методы PB SDK — без него вызовы могут висеть
  /// бесконечно при флапающем соединении (см. orders_repository).
  static const Duration _pbTimeout = Duration(seconds: 15);

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
    final records = await withPbAuthRetry(_ref,() => pb
        .collection('order_responses')
        .getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && status = "pending"',
            {'oid': orderId},
          ),
          sort: 'created',
        )
        .timeout(_pbTimeout));
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
    await withPbAuthRetry(_ref,() => pb.collection('order_responses').create(body: {
      'order_ref': orderId,
      'executor': me.id,
      'status': 'pending',
      'eta_min': ?etaMin,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    }).timeout(_pbTimeout));
  }

  /// Исключение, которое выбрасывается, если pending-отклик не найден к моменту
  /// accept/decline — обычно потому, что исполнитель отозвал его в этот же
  /// момент. UI должен показать сообщение и обновить экран откликов.
  static const String _responseGoneCode = 'response_gone';

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
    final list = await withPbAuthRetry(_ref,() => pb
        .collection('order_responses')
        .getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && executor = {:eid} && status = "pending"',
            {'oid': orderId, 'eid': executorId},
          ),
        )
        .timeout(_pbTimeout));
    if (list.isEmpty) {
      // Раньше тут было `return;` — заказчик видел тост-успех, а на сервере
      // ничего не менялось (отклик уже отозван исполнителем или принят
      // ранее). Кидаем исключение, UI отлавливает по коду и показывает
      // «Этот отклик уже недоступен», после чего перезагружает экран.
      throw OrderResponseGoneException(_responseGoneCode);
    }
    await withPbAuthRetry(_ref,() => pb
        .collection('order_responses')
        .update(list.first.id, body: {'status': 'accepted'})
        .timeout(_pbTimeout));
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
    final list = await withPbAuthRetry(_ref,() => pb
        .collection('order_responses')
        .getFullList(
          filter: pb.filter(
            'order_ref = {:oid} && executor = {:eid} && status = "pending"',
            {'oid': orderId, 'eid': executorId},
          ),
        )
        .timeout(_pbTimeout));
    if (list.isEmpty) {
      throw OrderResponseGoneException(_responseGoneCode);
    }
    await withPbAuthRetry(_ref,() =>
        pb.collection('order_responses').update(list.first.id, body: {
      'status': 'declined',
      'decline_reason': 'by_customer',
    }).timeout(_pbTimeout));
  }
}

/// Бросается accept/decline когда нужного pending-отклика уже нет
/// (исполнитель отозвал, заказчик уже принял другого, и т.п.).
class OrderResponseGoneException implements Exception {
  OrderResponseGoneException(this.code);
  final String code;
  @override
  String toString() => 'OrderResponseGoneException($code)';
}

final orderResponsesRepositoryProvider =
    Provider<OrderResponsesRepository>((ref) {
  return OrderResponsesRepository(ref.read(pocketbaseProvider), ref);
});
