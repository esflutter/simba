import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../mock/app_state.dart';
import '../models/models.dart';
import 'pocketbase_client.dart';

/// CRUD для коллекции `reviews`.
class ReviewsRepository {
  ReviewsRepository(this._pb, this._ref);

  final PocketBase? _pb;
  final Ref _ref;

  bool get _isLive => _pb != null;

  /// Отзывы, в которых пользователь — получатель.
  Future<List<Review>> forUser(String userId) async {
    if (!_isLive) {
      return _ref
          .read(appControllerProvider)
          .reviews
          .where((r) => r.toUserId == userId)
          .toList();
    }
    final pb = _pb!;
    final records = await pb.collection('reviews').getFullList(
          filter:
              'to_user = "$userId" && is_hidden = false && visible_after != "" && visible_after <= @now',
          sort: '-created',
        );
    return records.map(_fromRecord).toList();
  }

  /// Создать отзыв. Возвращает созданный `RecordModel` (или `null` в моке /
  /// при отсутствии auth) — удобно для invalidate выше по стеку.
  Future<RecordModel?> create({
    required String orderId,
    required String toUserId,
    required int rating,
    required String comment,
    required List<String> tags,
  }) async {
    if (!_isLive) {
      _ref.read(appControllerProvider.notifier).addReview(
            orderId: orderId,
            toUserId: toUserId,
            rating: rating,
            comment: comment,
            tags: tags,
          );
      return null;
    }
    final pb = _pb!;
    final me = pb.authStore.record;
    if (me == null) return null;
    return pb.collection('reviews').create(body: {
      'order_ref': orderId,
      'from_user': me.id,
      'to_user': toUserId,
      'rating': rating,
      'comment': comment,
      'tags': tags,
    });
  }

  Review _fromRecord(RecordModel r) {
    final tagsRaw = r.get<dynamic>('tags');
    final tags = (tagsRaw is List) ? tagsRaw.cast<String>() : const <String>[];
    return Review(
      id: r.id,
      fromUserId: r.getStringValue('from_user'),
      toUserId: r.getStringValue('to_user'),
      orderId: r.getStringValue('order_ref'),
      rating: r.getIntValue('rating'),
      comment: r.getStringValue('comment'),
      tags: tags,
      createdAt:
          DateTime.tryParse(r.getStringValue('created')) ?? DateTime.now(),
    );
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(ref.read(pocketbaseProvider), ref);
});
