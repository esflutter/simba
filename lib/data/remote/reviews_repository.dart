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
  ///
  /// [asRole] фильтрует отзывы по роли пользователя В ЗАКАЗЕ, по которому
  /// оставлен отзыв: `executor` — только отзывы о нём как об исполнителе
  /// (в заказе он был исполнителем), `customer` — как о заказчике. Это нужно,
  /// чтобы на карточке профиля рейтинг (берётся из агрегата по роли) совпадал
  /// со списком отзывов и распределением «звёзд». `null` — все отзывы (свой
  /// экран «Мои отзывы»).
  Future<List<Review>> forUser(String userId, {UserRole? asRole}) async {
    if (!_isLive) {
      // Мок: данных заказа под рукой нет, роль не фильтруем — отдаём все.
      return _ref
          .read(appControllerProvider)
          .reviews
          .where((r) => r.toUserId == userId)
          .toList();
    }
    final pb = _pb!;
    var filter = 'to_user = {:uid} && visible_after != "" && visible_after <= @now';
    if (asRole == UserRole.executor) {
      filter += ' && order_ref.executor = {:uid}';
    } else if (asRole == UserRole.customer) {
      filter += ' && order_ref.customer = {:uid}';
    }
    final records = await withPbAuthRetry(_ref,() => pb
        .collection('reviews')
        .getFullList(
          filter: pb.filter(filter, {'uid': userId}),
          sort: '-created',
          expand: 'from_user',
        )
        .timeout(const Duration(seconds: 15)));
    return records.map(_fromRecord).toList();
  }

  /// Отзывы, оставленные текущим пользователем (where `from_user = me`).
  /// Нужно для экрана истории, чтобы под карточкой завершённого заказа
  /// показать CTA «Оставить отзыв» только если он ещё не оставлен.
  ///
  /// На моке возвращает локальный `state.reviews` фильтрованный по `fromUserId`.
  /// На live делает запрос в PB; на любой ошибке возвращает пустой список,
  /// чтобы экран истории не падал в error-стейт из-за побочного провайдера.
  Future<List<Review>> mineFromMe() async {
    if (!_isLive) {
      final myId = _ref.read(appControllerProvider).user?.id ?? 'me';
      return _ref
          .read(appControllerProvider)
          .reviews
          .where((r) => r.fromUserId == myId || r.fromUserId == 'me')
          .toList();
    }
    final pb = _pb!;
    final me = pb.authStore.record;
    if (me == null) return const [];
    final records = await withPbAuthRetry(_ref, () => pb
        .collection('reviews')
        .getFullList(
          filter: pb.filter('from_user = {:uid}', {'uid': me.id}),
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
          expand: 'from_user',
        )
        .timeout(const Duration(seconds: 15)));
    return records.map(_fromRecord).toList();
  }

  /// Создать отзыв. Возвращает созданный `RecordModel` (или `null` в моке /
  /// при отсутствии auth) — удобно для invalidate выше по стеку.
  ///
  /// Идемпотентность через серверный уникальный индекс `idx_reviews_unique`
  /// `(order_ref, from_user)`. При сетевом флапе после успешного INSERT
  /// повторный create вернёт 400/409 на unique-constraint; ловим и
  /// возвращаем уже существующую запись — для UI это idempotent-успех,
  /// тост «отзыв мог отправиться» больше не нужен.
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
    try {
      return await withPbAuthRetry(
          _ref,
          () => pb.collection('reviews').create(body: {
                'order_ref': orderId,
                'from_user': me.id,
                'to_user': toUserId,
                'rating': rating,
                'comment': comment,
                'tags': tags,
              }).timeout(const Duration(seconds: 15)));
    } on ClientException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 409) {
        try {
          final existing = await withPbAuthRetry(
              _ref,
              () => pb
                  .collection('reviews')
                  .getFirstListItem(
                    pb.filter(
                      'order_ref = {:oid} && from_user = {:uid}',
                      {'oid': orderId, 'uid': me.id},
                    ),
                  )
                  .timeout(const Duration(seconds: 10)));
          return existing; // запись уже была — idempotent-успех
        } catch (_) {/* реальная ошибка валидации — пробрасываем */}
      }
      rethrow;
    }
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

    // expand.from_user — single-rel. PB SDK 0.22 рекомендует доступ через
     // get<RecordModel>("expand.from_user") вместо устаревшего .expand.
    final expandedFrom = r.get<RecordModel?>('expand.from_user');
    final fromUserName = expandedFrom?.getStringValue('name') ?? '';
    String? fromUserPhotoUrl;
    if (expandedFrom != null && _pb != null) {
      final fname = expandedFrom.getStringValue('photo');
      if (fname.isNotEmpty) {
        fromUserPhotoUrl = pbFileUrl(
          _pb,
          collection: expandedFrom.collectionId,
          recordId: expandedFrom.id,
          filename: fname,
        );
      }
    }

    return Review(
      id: r.id,
      fromUserId: r.getStringValue('from_user'),
      toUserId: r.getStringValue('to_user'),
      orderId: r.getStringValue('order_ref'),
      rating: r.getIntValue('rating'),
      comment: r.getStringValue('comment'),
      tags: tags,
      createdAt: createdAt,
      fromUserName: fromUserName,
      fromUserPhotoUrl: fromUserPhotoUrl,
    );
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  return ReviewsRepository(ref.read(pocketbaseProvider), ref);
});
