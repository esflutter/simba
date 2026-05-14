import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/utils/pb_date.dart';
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
    final records = await withPbAuthRetry(_ref,() => pb
        .collection('reviews')
        .getFullList(
          filter: pb.filter(
            'to_user = {:uid} && is_hidden = false && visible_after != "" && visible_after <= @now',
            {'uid': userId},
          ),
          sort: '-created',
        )
        .timeout(const Duration(seconds: 15)));
    return records.map(_fromRecord).toList();
  }

  /// Все отзывы по конкретному заказу. Нужно, чтобы определить, оставил ли
  /// текущий пользователь свой отзыв — без этого live-кнопка «Оставить
  /// отзыв» дублировалась бы после успешной отправки (state.reviews в live
  /// не наполняется маппером, и hasMyReview через локальный стейт всегда
  /// false).
  Future<List<Review>> forOrder(String orderId) async {
    if (!_isLive) {
      return _ref
          .read(appControllerProvider)
          .reviews
          .where((r) => r.orderId == orderId)
          .toList();
    }
    final pb = _pb!;
    final records = await withPbAuthRetry(_ref,() => pb
        .collection('reviews')
        .getFullList(
          filter: pb.filter('order_ref = {:oid}', {'oid': orderId}),
          sort: '-created',
        )
        .timeout(const Duration(seconds: 15)));
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
    return withPbAuthRetry(_ref,() => pb.collection('reviews').create(body: {
      'order_ref': orderId,
      'from_user': me.id,
      'to_user': toUserId,
      'rating': rating,
      'comment': comment,
      'tags': tags,
    }).timeout(const Duration(seconds: 15)));
  }

  Review _fromRecord(RecordModel r) {
    // Раньше использовался `(tagsRaw as List).cast<String>()` — это типовая
    // ловушка Dart: cast<String>() — ленивый, бросает на первом не-String
    // элементе при итерации. Если в БД случайно появится null/число — весь
    // экран отзывов падал. Сейчас аккуратно фильтруем.
    final tagsRaw = r.get<dynamic>('tags');
    final List<String> tags;
    if (tagsRaw is List) {
      tags = tagsRaw
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } else {
      tags = const <String>[];
    }

    // Битая `created` — крайне редкая ситуация, но fallback на `DateTime.now()`
    // дал бы свежую дату старому отзыву и поломал бы сортировку. Используем
    // sentinel «эпоха», чтобы такие отзывы ушли в конец списка и было видно
    // в логах через debugPrint в parsePbDate.
    final createdAt =
        parsePbDate(r.getStringValue('created')) ?? DateTime.fromMillisecondsSinceEpoch(0);

    return Review(
      id: r.id,
      fromUserId: r.getStringValue('from_user'),
      toUserId: r.getStringValue('to_user'),
      orderId: r.getStringValue('order_ref'),
      rating: r.getIntValue('rating'),
      comment: r.getStringValue('comment'),
      tags: tags,
      createdAt: createdAt,
    );
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(ref.read(pocketbaseProvider), ref);
});
