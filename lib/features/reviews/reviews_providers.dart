import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/reviews_repository.dart';

/// Отзывы на указанного юзера. На моках вернёт `state.reviews` фильтрованные
/// по `toUserId`. На live — реальный список из PocketBase.
final reviewsForUserProvider =
    FutureProvider.family<List<Review>, String>((ref, userId) async {
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
