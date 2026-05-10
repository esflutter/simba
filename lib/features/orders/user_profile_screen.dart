import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId, this.orderId});
  final String userId;
  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final user = userById(userId);
    final allReviews = state.reviews;
    final reviews = allReviews
        .where((r) => r.toUserId == userId || r.toUserId == 'me')
        .toList();
    final order = orderId == null
        ? null
        : [...state.myOrders, ...state.orders]
            .cast<Order?>()
            .firstWhere((o) => o?.id == orderId, orElse: () => null);
    final isAcceptedExecutor =
        order != null && order.executorId == userId;
    final isPendingCandidate = order != null &&
        order.status == OrderStatus.open &&
        order.responses.contains(userId);
    final accepted = isAcceptedExecutor;

    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      ratingDistribution[r.rating] = (ratingDistribution[r.rating] ?? 0) + 1;
    }
    final maxCount = ratingDistribution.values.fold<int>(
      0,
      (p, c) => c > p ? c : p,
    );
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
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
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
                            color: AppColors.surfaceVariant,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
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
                              if (accepted)
                                Container(
                                  margin: EdgeInsets.only(bottom: 4.h),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                  child: Text(
                                    'Исполнитель принят',
                                    style: AppText.caption(
                                      color: Colors.white,
                                      weight: FontWeight.w500,
                                    ).copyWith(height: 1.33),
                                  ),
                                ),
                              Text(
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
                              SizedBox(height: 4.h),
                              Text(
                                user.phone,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  height: 1.50,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ContactButton(
                            label: 'Написать',
                            background: AppColors.surface,
                            color: Colors.black,
                            onTap: () => _showContactSheet(context, user.phone),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: _ContactButton(
                            label: 'Позвонить',
                            background: AppColors.primary,
                            color: const Color(0xFFF5F5F5),
                            onTap: () => _callPhone(user.phone),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    AppCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.h),
                        child: Column(
                          children: [
                            Icon(
                              IconsaxPlusLinear.star,
                              size: 56.r,
                              color: AppColors.textTertiary,
                            ),
                            SizedBox(height: 12.h),
                            Text(
                              'Нет отзывов',
                              style: AppText.body(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    AppCard(
                      child: _RatingSummary(
                        average: avgRating,
                        total: reviews.length,
                        distribution: ratingDistribution,
                        maxCount: maxCount,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ...reviews.map(
                      (r) => Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: AppCard(
                          padding: EdgeInsets.all(12.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16.r,
                                    backgroundColor: AppColors.surfaceVariant,
                                    child: Icon(
                                      IconsaxPlusLinear.user,
                                      color: AppColors.primary,
                                      size: 18.r,
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    userById(r.fromUserId).name,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                      height: 1.40,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Padding(
                                      padding: EdgeInsets.only(right: 2.w),
                                      child: Icon(
                                        IconsaxPlusBold.star_1,
                                        size: 14.r,
                                        color: i < r.rating
                                            ? AppColors.star
                                            : AppColors.divider,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    DateFormat('dd.MM.yyyy').format(r.createdAt),
                                    style: AppText.caption(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                r.comment,
                                style: AppText.bodySmall(
                                  color: AppColors.textSecondary,
                                ).copyWith(height: 1.40),
                              ),
                              if (r.tags.isNotEmpty) ...[
                                SizedBox(height: 8.h),
                                Wrap(
                                  spacing: 8.w,
                                  runSpacing: 6.h,
                                  children: r.tags.map((t) => CategoryChip(t)).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (isPendingCandidate)
            _CandidateActionBar(
              onAccept: () {
                ref
                    .read(appControllerProvider.notifier)
                    .acceptResponse(orderId!, userId);
                Navigator.of(context).pop();
              },
              onDecline: () {
                ref
                    .read(appControllerProvider.notifier)
                    .declineResponse(orderId!, userId);
                Navigator.of(context).pop();
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

class _CandidateActionBar extends StatelessWidget {
  const _CandidateActionBar({required this.onAccept, required this.onDecline});
  final VoidCallback onAccept;
  final VoidCallback onDecline;

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
                onTap: onAccept,
              ),
              SizedBox(height: 8.h),
              _ActionBarButton(
                label: 'Отклонить',
                background: AppColors.surfaceVariant,
                textColor: AppColors.error,
                onTap: onDecline,
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
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
                color: textColor,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    IconsaxPlusLinear.message_text_1,
                    color: AppColors.primary,
                    size: 24.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Написать',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.20,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.all(4.r),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppColors.primary,
                        size: 24.r,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Container(height: 1, color: AppColors.divider),
              SizedBox(height: 24.h),
              // Messengers
              Row(
                children: [
                  _Messenger(
                    label: "What's App",
                    onTap: () => _openMessenger(context, 'whatsapp'),
                    builder: (s) => Container(
                      width: s,
                      height: s,
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D366),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.phone, color: Colors.white, size: s * 0.5),
                    ),
                  ),
                  SizedBox(width: 24.w),
                  _Messenger(
                    label: 'Telegram',
                    onTap: () => _openMessenger(context, 'telegram'),
                    builder: (s) => Container(
                      width: s,
                      height: s,
                      decoration: const BoxDecoration(
                        color: Color(0xFF26A5E4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.send_rounded, color: Colors.white, size: s * 0.5),
                    ),
                  ),
                  SizedBox(width: 24.w),
                  _Messenger(
                    label: 'MAX',
                    onTap: () => _openMessenger(context, 'max'),
                    builder: (s) => Container(
                      width: s,
                      height: s,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7B45FF), Color(0xFF26A5E4)],
                        ),
                        borderRadius: BorderRadius.circular(s * 0.25),
                      ),
                      child: Icon(Icons.chat_bubble, color: Colors.white, size: s * 0.45),
                    ),
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

  void _openMessenger(BuildContext context, String app) {
    // TODO: deep-links на конкретные мессенджеры — пока заглушка.
    Navigator.of(context).pop();
  }
}

class _Messenger extends StatelessWidget {
  const _Messenger({
    required this.label,
    required this.builder,
    required this.onTap,
  });

  final String label;
  final Widget Function(double size) builder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = 64.r;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          builder(iconSize),
          SizedBox(height: 8.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              height: 1.38,
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
    required this.maxCount,
  });

  final double average;
  final int total;
  final Map<int, int> distribution;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final filledStars = average.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              average.toStringAsFixed(1).replaceAll('.', ','),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                height: 1.20,
              ),
            ),
            SizedBox(width: 8.w),
            ...List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(right: 2.w),
                child: Icon(
                  IconsaxPlusBold.star_1,
                  size: 18.r,
                  color: i < filledStars ? AppColors.star : AppColors.divider,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Text(
          '$total ${_pluralReviews(total)}',
          style: AppText.bodySmall(color: AppColors.textSecondary)
              .copyWith(height: 1.38),
        ),
        SizedBox(height: 12.h),
        for (final stars in [5, 4, 3, 2, 1])
          Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    IconsaxPlusBold.star_1,
                    size: 12.r,
                    color: i < stars ? AppColors.star : AppColors.divider,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: maxCount == 0 ? 0 : (distribution[stars] ?? 0) / maxCount,
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
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
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
