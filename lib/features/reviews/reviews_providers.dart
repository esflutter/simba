import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/pocketbase_client.dart';
import '../../data/remote/reviews_repository.dart';

/// Отзывы на указанного юзера. На моках вернёт `state.reviews` фильтрованные
/// по `toUserId`. На live — реальный список из PocketBase.
///
/// `autoDispose` — чтобы кэш не жил вечно: при возврате на экран profile
/// делается свежий запрос, а не показывается stale-список двухчасовой давности.
/// Отзывы о пользователе С УЧЁТОМ РОЛИ (исполнитель/заказчик в заказе, по
/// которому оставлен отзыв). Нужен на чужом профиле, чтобы рейтинг (агрегат
/// по роли), число отзывов и распределение «звёзд» были согласованы между
/// собой и совпадали со списком откликов. Для своего экрана «Мои отзывы»
/// по-прежнему используется reviewsForUserProvider (все отзывы).
final reviewsForUserAsRoleProvider = FutureProvider.autoDispose
    .family<List<Review>, ({String userId, UserRole role})>((ref, args) async {
  return ref
      .read(reviewsRepositoryProvider)
      .forUser(args.userId, asRole: args.role);
});

final reviewsForUserProvider =
    FutureProvider.autoDispose.family<List<Review>, String>((ref, userId) async {
  // Без catch: мок-режим обслуживает сам репозиторий (forUser при pb==null
  // возвращает state.reviews и не бросает). В live сетевую ошибку отдаём
  // наверх, чтобы экран отзывов показал «не удалось загрузить» с повтором,
  // а не «Нет отзывов» и нулевой рейтинг при сбое сети.
  return ref.read(reviewsRepositoryProvider).forUser(userId);
});

/// Отзывы по конкретному заказу. Используется на «деталях заказа» для
/// определения, оставил ли текущий пользователь свой отзыв — это позволяет
/// прятать кнопку «Оставить отзыв» после успешной отправки в live-режиме
/// (где `state.reviews` маппером не наполняется).
final reviewsByOrderProvider = FutureProvider.autoDispose
    .family<List<Review>, String>((ref, orderId) async {
  // В мок-режиме (нет live PocketBase) локальный стейт — корректный
  // источник. В live ошибку НЕ глушим пустым списком: иначе экран деталей
  // решает, что отзыва нет, и на плохой связи снова рисует кнопку
  // «Оставить отзыв» по уже отрецензированному заказу. Пробрасываем ошибку
  // наверх — экран трактует её как «состояние неизвестно» и кнопку не
  // показывает (как и соседний провайдер отзывов на пользователя).
  final pb = ref.read(pocketbaseProvider);
  if (pb == null) {
    return ref
        .read(appControllerProvider)
        .reviews
        .where((r) => r.orderId == orderId)
        .toList();
  }
  return ref.read(reviewsRepositoryProvider).forOrder(orderId);
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
