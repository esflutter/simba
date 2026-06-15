import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/backend_error.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/pocketbase_client.dart' show pocketbaseProvider;
import 'reviews_providers.dart';

class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  /// PB realtime-подписка на коллекцию reviews. Без неё новый отзыв,
  /// пришедший в момент когда юзер смотрит список своих отзывов, не
  /// появляется до pull-to-refresh.
  Future<void> Function()? _reviewsUnsub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeReviews());
  }

  Future<void> _subscribeReviews() async {
    if (!mounted) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    final myId = ref.read(appControllerProvider).user?.id;
    if (myId == null || myId.isEmpty) return;
    try {
      final unsub = await pb.collection('reviews').subscribe('*', (e) {
        if (!mounted) return;
        // PB rules уже фильтруют события на стороне сервера — нам
        // приходят только видимые отзывы. На клиенте всё равно
        // отбрасываем чужие, чтобы не делать лишний запрос для отзыва
        // на другого юзера (где я был автором).
        final rec = e.record;
        if (rec == null) {
          ref.invalidate(reviewsForUserProvider(myId));
          return;
        }
        if (rec.getStringValue('to_user') == myId) {
          ref.invalidate(reviewsForUserProvider(myId));
        }
      });
      if (!mounted) {
        await unsub();
        return;
      }
      _reviewsUnsub = unsub;
    } catch (_) {/* WS недоступен — pull-to-refresh всё ещё работает */}
  }

  @override
  void dispose() {
    final unsub = _reviewsUnsub;
    _reviewsUnsub = null;
    if (unsub != null) {
      // ignore: discarded_futures
      unsub();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Берём отзывы из репозитория (live или mock-fallback) для текущего юзера.
    // Пустой массив (data:[]) — валидный ответ для нового юзера: НЕ подменяем
    // его моком, иначе пользователь увидит чужие demo-отзывы.
    // На loading возвращаем null → ниже рендерим спиннер, чтобы не мигать
    // empty-state'ом «Нет отзывов» до прихода реальных данных.
    final me = ref.watch(appControllerProvider.select((s) => s.user));
    final myId = me?.id ?? 'me';
    final asyncReviews = ref.watch(reviewsForUserProvider(myId));
    // Различаем три состояния:
    //   loading → спиннер
    //   error   → плашка «не удалось загрузить» с retry (раньше тихо
    //             падали на мок-стейт и юзер видел «Нет отзывов», даже
    //             если на сервере отзывы реально есть)
    //   data    → реальный список
    final bool isLoading =
        asyncReviews.isLoading && !asyncReviews.hasValue;
    final bool hasError = asyncReviews.hasError;
    final List<Review> reviews = asyncReviews.when(
      data: (list) => list,
      loading: () => const <Review>[],
      error: (_, _) => const <Review>[],
    );
    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    final avgRating = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44.h,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: const AppBackButton(),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Отзывы',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.29,
                          letterSpacing: -0.43,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Body ──
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : hasError && reviews.isEmpty
                ? _ReviewsLoadError(
                    onRetry: () => ref.invalidate(reviewsForUserProvider(myId)),
                  )
                : reviews.isEmpty
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      16.h,
                      16.w,
                      MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    child: Column(
                      children: [
                        _RatingSummaryCard(
                          average: avgRating,
                          total: reviews.length,
                          distribution: ratingDistribution,
                        ),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/empty_reviews.webp',
                                  width: 80.r,
                                  height: 80.r,
                                ),
                                SizedBox(height: 24.h),
                                Text(
                                  'Нет отзывов',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                    letterSpacing: -0.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(reviewsForUserProvider(myId));
                      try {
                        await ref.read(reviewsForUserProvider(myId).future);
                      } catch (e) {
                        if (!context.mounted) return;
                        AppToast.error(context, humanizeBackendError(e));
                      }
                    },
                    child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16.w,
                      16.h,
                      16.w,
                      MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    // +1 — это карточка-сводка рейтинга в самом верху,
                    // дальше идут сами отзывы. ListView.builder ленив,
                    // на 100+ отзывах синхронный ListView(children:) давал
                    // jank при открытии экрана.
                    itemCount: reviews.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: _RatingSummaryCard(
                            average: avgRating,
                            total: reviews.length,
                            distribution: ratingDistribution,
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: _ReviewCard(review: reviews[i - 1]),
                      );
                    },
                  ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummaryCard extends StatelessWidget {
  const _RatingSummaryCard({
    required this.average,
    required this.total,
    required this.distribution,
  });

  final double average;
  final int total;
  final Map<int, int> distribution;

  @override
  Widget build(BuildContext context) {
    final filledStars = average.round();
    final hasReviews = total > 0;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                hasReviews ? formatRating(average) : '0',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.20,
                ),
              ),
              SizedBox(width: 4.w),
              if (hasReviews)
                ...List.generate(
                  5,
                  (i) => Padding(
                    padding: EdgeInsets.only(right: i == 4 ? 0 : 2.w),
                    child: Image.asset(
                      i < filledStars
                          ? 'assets/images/icon_ranking.webp'
                          : 'assets/images/icon_star_empty.webp',
                      width: 20.r,
                      height: 20.r,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            '$total ${_pluralReviews(total)}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.60),
              fontSize: 13.sp,
              fontWeight: FontWeight.w400,
              height: 1.38,
            ),
          ),
          SizedBox(height: 8.h),
          for (final stars in [5, 4, 3, 2, 1]) ...[
            _DistributionRow(
              filled: stars,
              count: distribution[stars] ?? 0,
              total: total,
            ),
            if (stars > 1) SizedBox(height: 8.h),
          ],
        ],
      ),
    );
  }

  String _pluralReviews(int n) {
    final lastTwo = n % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'отзывов';
    final last = n % 10;
    if (last == 1) return 'отзыв';
    if (last >= 2 && last <= 4) return 'отзыва';
    return 'отзывов';
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.filled,
    required this.count,
    required this.total,
  });

  final int filled;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...List.generate(
          5,
          (i) => Padding(
            padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
            child: Image.asset(
              i < filled
                  ? 'assets/images/icon_ranking.webp'
                  : 'assets/images/icon_star_empty.webp',
              width: 14.r,
              height: 14.r,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 8.h,
              backgroundColor: AppColors.surfaceVariant,
              color: AppColors.star,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          width: 24.w,
          child: Text(
            '$count',
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              height: 1.38,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    // Приоритет: имя из expand.from_user (live PB) → локальный мок-юзер →
    // «Пользователь». Раньше использовали только userById, который для
    // PB-id ничего не находит, и все отзывы становились «Пользователь».
    final authorName = review.fromUserName.isNotEmpty
        ? review.fromUserName
        : (userById(review.fromUserId)?.name ?? 'Без имени');
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ReviewAvatar(photoUrl: review.fromUserPhotoUrl),
              SizedBox(width: 4.w),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: Text(
                    authorName,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.33,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(
                5,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
                  child: Image.asset(
                    i < review.rating
                        ? 'assets/images/icon_ranking.webp'
                        : 'assets/images/icon_star_empty.webp',
                    width: 14.r,
                    height: 14.r,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                DateFormat('dd.MM.yyyy', 'ru_RU')
                    .format(review.createdAt.toLocal()),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // Лимит на 5 строк с многоточием: длинный отзыв (до 1000
          // символов в БД) превращал карточку в простыню высотой
          // ~400px, ломая визуальную ритмику списка. Полный текст
          // открывается тапом по карточке в детали отзыва (TODO для
          // отдельного screen — пока обрезка достаточна).
          Text(
            review.comment,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w400,
              height: 1.38,
            ),
          ),
          if (review.tags.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: review.tags
                  .map(
                    (t) => Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        reviewTagLabel(t),
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      IconsaxPlusLinear.user,
      color: AppColors.primary,
      size: 20.r,
    );
    return Container(
      width: 32.r,
      height: 32.r,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? fallback
          // width/height передаём явно — иначе AppNetworkImage декодирует
          // аватар в полном разрешении (часто 512+px) ради кружка 32px и
          // зря держит память на ленте из десятков отзывов.
          : AppNetworkImage(
              url: photoUrl!,
              fallback: fallback,
              width: 32.r,
              height: 32.r,
            ),
    );
  }
}


/// Плашка ошибки загрузки отзывов с кнопкой повтора. До этого при
/// сетевой ошибке экран показывал «Нет отзывов» через fallback на
/// мок-стейт — пользователь думал, что отзывов реально нет.
class _ReviewsLoadError extends StatelessWidget {
  const _ReviewsLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.cloud_cross,
                size: 64.r, color: AppColors.textTertiary),
            SizedBox(height: 16.h),
            Text(
              'Не удалось загрузить отзывы',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Проверьте подключение к интернету и попробуйте снова.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w400,
                height: 1.33,
              ),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: 200.w,
              child: PrimaryButton(label: 'Попробовать снова', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}
