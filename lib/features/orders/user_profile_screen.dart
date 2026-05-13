import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/order_responses_repository.dart';
import '../../data/remote/orders_repository.dart';
import '../../data/remote/users_repository.dart';
import '../reviews/reviews_providers.dart' show reviewsForUserProvider;
import 'order_details_screen.dart' show orderByIdProvider;
import 'responses_screen.dart' show pendingExecutorIdsProvider;

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId, this.orderId});
  final String userId;
  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final user = userById(userId);
    // Отзывы берём из репозитория (live → PB, иначе мок-fallback внутри
    // провайдера). Раньше код читал `state.reviews` напрямую — в live этот
    // список всегда пуст, поэтому отзывы на профиле не отображались.
    final asyncReviews = ref.watch(reviewsForUserProvider(userId));
    final reviews = asyncReviews.maybeWhen(
      data: (xs) => xs,
      orElse: () =>
          state.reviews.where((r) => r.toUserId == userId).toList(),
    );
    final order = orderId == null
        ? null
        : [...state.myOrders, ...state.orders]
            .cast<Order?>()
            .firstWhere((o) => o?.id == orderId, orElse: () => null);
    final isPendingCandidate = order != null &&
        order.status == OrderStatus.open &&
        order.responses.contains(userId);
    final canContact = order != null &&
        (order.status == OrderStatus.accepted ||
            order.status == OrderStatus.awaitingPayment) &&
        (order.customerId == userId || order.executorId == userId);

    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    final avgRating = reviews.isEmpty
        ? user.rating
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: const AppBackButton(),
                ),
              ),
            ),
          ),
          Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16.w,
                  8.h,
                  16.w,
                  isPendingCandidate
                      ? 0
                      : 16.h + MediaQuery.of(context).viewPadding.bottom,
                ),
                children: [
                  AppCard(
                    padding: EdgeInsets.all(16.w),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Row(
                      children: [
                        Container(
                          width: 56.r,
                          height: 56.r,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: user.photoPath != null
                              ? (user.photoPath!.startsWith('http')
                                  ? Image.network(
                                      user.photoPath!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        IconsaxPlusLinear.user,
                                        color: AppColors.primary,
                                        size: 32.r,
                                      ),
                                    )
                                  : Image.file(
                                      File(user.photoPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        IconsaxPlusLinear.user,
                                        color: AppColors.primary,
                                        size: 32.r,
                                      ),
                                    ))
                              : Icon(
                                  IconsaxPlusLinear.user,
                                  color: AppColors.primary,
                                  size: 32.r,
                                ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      user.name,
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.w600,
                                        height: 1.20,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (user.hasTools) ...[
                                    SizedBox(width: 8.w),
                                    Image.asset(
                                      'assets/images/icon_tools.png',
                                      width: 16.r,
                                      height: 16.r,
                                    ),
                                  ],
                                  if (user.hasTransport) ...[
                                    SizedBox(width: 8.w),
                                    Image.asset(
                                      'assets/images/icon_transport.png',
                                      width: 20.r,
                                      height: 16.r,
                                    ),
                                  ],
                                ],
                              ),
                              if (canContact) ...[
                                SizedBox(height: 4.h),
                                Consumer(builder: (context, ref, _) {
                                  final args = ContactPhoneArgs(
                                    userId: userId,
                                    orderId: orderId!,
                                  );
                                  final phoneAsync =
                                      ref.watch(contactPhoneProvider(args));
                                  final phone = phoneAsync.maybeWhen(
                                    data: (p) => p ?? user.phone,
                                    orElse: () => user.phone,
                                  );
                                  return Text(
                                    phone,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w600,
                                      height: 1.50,
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canContact) ...[
                    SizedBox(height: 8.h),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Consumer(builder: (context, ref, _) {
                        final args = ContactPhoneArgs(
                          userId: userId,
                          orderId: orderId!,
                        );
                        final phone = ref
                            .watch(contactPhoneProvider(args))
                            .maybeWhen(
                              data: (p) => p ?? user.phone,
                              orElse: () => user.phone,
                            );
                        return Row(
                          children: [
                            Expanded(
                              child: _ContactButton(
                                label: 'Написать',
                                background: AppColors.surface,
                                color: Colors.black,
                                onTap: () => _showContactSheet(context, phone),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: _ContactButton(
                                label: 'Позвонить',
                                background: AppColors.primary,
                                color: const Color(0xFFF5F5F5),
                                onTap: () => _callPhone(phone),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                  SizedBox(height: 8.h),
                  Text(
                    'Отзывы',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.54,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  if (reviews.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 64.h),
                      child: Column(
                        children: [
                          Icon(
                            IconsaxPlusLinear.star_1,
                            size: 80.r,
                            color: AppColors.star,
                          ),
                          SizedBox(height: 24.h),
                          Text(
                            'Нет отзывов',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              letterSpacing: -0.45,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    AppCard(
                      padding: EdgeInsets.all(12.w),
                      borderRadius: BorderRadius.circular(10.r),
                      child: _RatingSummary(
                        average: avgRating,
                        total: reviews.length,
                        distribution: ratingDistribution,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ...reviews.map(
                      (r) => Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: AppCard(
                          padding: EdgeInsets.all(12.w),
                          borderRadius: BorderRadius.circular(12.r),
                          child: _ReviewItem(review: r),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (isPendingCandidate)
            _CandidateActionBar(
              onAccept: () async {
                try {
                  await ref
                      .read(orderResponsesRepositoryProvider)
                      .accept(orderId!, userId);
                  if (!context.mounted) return;
                  ref.invalidate(myOrdersStreamProvider);
                  ref.invalidate(feedOrdersProvider);
                  ref.invalidate(pendingExecutorIdsProvider(orderId!));
                  ref.invalidate(orderByIdProvider(orderId!));
                  AppToast.show(context, 'Исполнитель принят');
                  // После принятия остальные отклики автоматически отклонены —
                  // экран откликов под нами теперь пустой. Убираем его из
                  // стека (go_router-native): сначала pop профиля, потом
                  // pushReplacement на тот же профиль — экран откликов
                  // заменяется и в стеке остаётся [order → profile]. Back
                  // теперь корректно ведёт на детали заказа.
                  context.pop();
                  context.pushReplacement(
                    '/order/$orderId/user/$userId',
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  AppToast.show(context, 'Ошибка. Попробуйте позже');
                }
              },
              onDecline: () async {
                final wasLast = order.responses.length == 1;
                try {
                  await ref
                      .read(orderResponsesRepositoryProvider)
                      .decline(orderId!, userId);
                  if (!context.mounted) return;
                  ref.invalidate(myOrdersStreamProvider);
                  ref.invalidate(feedOrdersProvider);
                  ref.invalidate(pendingExecutorIdsProvider(orderId!));
                  ref.invalidate(orderByIdProvider(orderId!));
                  AppToast.show(context, 'Исполнитель отклонён');
                  context.pop();
                  if (wasLast) context.pop();
                } catch (_) {
                  if (!context.mounted) return;
                  AppToast.show(context, 'Ошибка. Попробуйте позже');
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context, String phone) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(phone: phone),
    );
  }

  Future<void> _callPhone(String phone) async {
    final sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (sanitized.isEmpty) return;
    final uri = Uri.parse('tel:$sanitized');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }
}

class _CandidateActionBar extends StatefulWidget {
  const _CandidateActionBar({required this.onAccept, required this.onDecline});
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  State<_CandidateActionBar> createState() => _CandidateActionBarState();
}

class _CandidateActionBarState extends State<_CandidateActionBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.r),
          topRight: Radius.circular(16.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18.80,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBarButton(
                label: 'Принять',
                background: AppColors.primary,
                textColor: Colors.white,
                onTap: _busy ? null : () => _run(widget.onAccept),
              ),
              SizedBox(height: 8.h),
              _ActionBarButton(
                label: 'Отклонить',
                background: AppColors.surfaceVariant,
                textColor: AppColors.error,
                onTap: _busy ? null : () => _run(widget.onDecline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBarButton extends StatelessWidget {
  const _ActionBarButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });
  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? AppColors.surfaceVariant : background,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 50.h,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: disabled ? AppColors.textTertiary : textColor,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.label,
    required this.background,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          height: 36.h,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/images/icon_messages.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Написать',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.29,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(6.r),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppColors.primary,
                        size: 20.r,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Container(height: 1, color: AppColors.divider),
              SizedBox(height: 22.h),
              Row(
                children: [
                  _Messenger(
                    label: 'WhatsApp',
                    asset: 'assets/images/icon_whatsapp.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _Messenger(
                    label: 'Telegram',
                    asset: 'assets/images/icon_telegram.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _Messenger(
                    label: 'MAX',
                    asset: 'assets/images/icon_max.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _Messenger extends StatelessWidget {
  const _Messenger({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(asset, width: 60.r, height: 60.r),
          SizedBox(height: 5.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              height: 1.18,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              average.toStringAsFixed(1).replaceAll('.', ','),
              style: TextStyle(
                color: Colors.black,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                height: 1.20,
              ),
            ),
            SizedBox(width: 4.w),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...List.generate(
                5,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 1.w),
                  child: Image.asset(
                    i < stars
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
                    value: total == 0 ? 0 : (distribution[stars] ?? 0) / total,
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
                  '${distribution[stars] ?? 0}',
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.38,
                  ),
                ),
              ),
            ],
          ),
          if (stars > 1) SizedBox(height: 8.h),
        ],
      ],
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

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    final author = userById(review.fromUserId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32.r,
              height: 32.r,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: author.photoPath != null
                  ? (author.photoPath!.startsWith('http')
                      ? Image.network(
                          author.photoPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            IconsaxPlusLinear.user,
                            color: AppColors.primary,
                            size: 20.r,
                          ),
                        )
                      : Image.file(
                          File(author.photoPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            IconsaxPlusLinear.user,
                            color: AppColors.primary,
                            size: 20.r,
                          ),
                        ))
                  : Icon(
                      IconsaxPlusLinear.user,
                      color: AppColors.primary,
                      size: 20.r,
                    ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                author.name,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.33,
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
              DateFormat('dd.MM.yyyy').format(review.createdAt),
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
        Text(
          review.comment,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.60),
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
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
