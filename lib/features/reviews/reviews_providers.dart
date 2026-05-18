import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/reviews_repository.dart';

/// Отзывы на указанного юзера. На моках вернёт `state.reviews` фильтрованные
/// по `toUserId`. На live — реальный список из PocketBase.
///
/// `autoDispose` — чтобы кэш не жил вечно: при возврате на экран profile
/// делается свежий запрос, а не показывается stale-список двухчасовой давности.
final reviewsForUserProvider =
    FutureProvider.autoDispose.family<List<Review>, String>((ref, userId) async {
  try {
    return await ref.read(reviewsRepositoryProvider).forUser(userId);
  } catch (_) {
    // Fallback на мок-стейт (например, при сетевой ошибке).
    return ref
        .read(appControllerProvider)
        .reviews
        .where((r) => r.toUserId == userId)
        .toList();
  }
});

/// Отзывы по конкретному заказу. Используется на «деталях заказа» для
/// определения, оставил ли текущий пользователь свой отзыв — это позволяет
/// прятать кнопку «Оставить отзыв» после успешной отправки в live-режиме
/// (где `state.reviews` маппером не наполняется).
final reviewsByOrderProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, orderId) async {
  try {
    return await ref.read(reviewsRepositoryProvider).forOrder(orderId);
  } catch (_) {
    // Fallback на локальный стейт (мок-режим / сетевая ошибка).
    return ref
        .read(appControllerProvider)
        .reviews
        .where((r) => r.orderId == orderId)
        .toList();
  }
});

/// Set order_id'ов, по которым текущий пользователь уже оставил отзыв.
/// Нужен экрану истории, чтобы рисовать «Оставить отзыв» только под теми
/// карточками, по которым отзыва ещё нет — без N round-trip'ов
/// reviewsByOrderProvider на каждую запись.
///
/// Не autoDispose: одна выборка переиспользуется обоими табами
/// (Размещённые / Выполненные) и при возвратах на экран. Свежесть
/// обеспечивается через `ref.invalidate(myReviewedOrderIdsProvider)`
/// после успешной отправки отзыва.
final myReviewedOrderIdsProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final reviews = await ref.read(reviewsRepositoryProvider).mineFromMe();
    return reviews.map((r) => r.orderId).toSet();
  } catch (_) {
    final myId = ref.read(appControllerProvider).user?.id ?? 'me';
    return ref
        .read(appControllerProvider)
        .reviews
        .where((r) => r.fromUserId == myId || r.fromUserId == 'me')
        .map((r) => r.orderId)
        .toSet();
  }
});
