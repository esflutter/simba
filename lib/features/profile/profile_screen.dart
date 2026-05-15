import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_network_image.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart';
import '../../data/remote/pocketbase_client.dart';
import '../reviews/reviews_providers.dart' show reviewsForUserProvider;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Подписываемся отдельно на user — иначе ConsumerWidget может пропустить
    // ребилд из-за const-канонизации screens в HomeShell.
    final user = ref.watch(appControllerProvider.select((s) => s.user));
    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    // Считаем рейтинг из реальных отзывов на текущего юзера, а не из
    // user.rating (он у новых пользователей 0). В live тянем отзывы через
    // reviewsForUserProvider (PB), на ошибке падаем в state.reviews.
    //
    // Пока запрос грузится — возвращаем null, и _ProfileCard скрывает блок
    // рейтинга. Иначе на доли секунды показался бы «0.0», который потом
    // сменился бы на реальный рейтинг (или наоборот — пустота на реальный).
    final myId = user.id;
    final asyncReviews = ref.watch(reviewsForUserProvider(myId));
    final myReviews = asyncReviews.when(
      data: (xs) => xs,
      loading: () => null,
      error: (_, _) => ref
          .watch(appControllerProvider.select((s) => s.reviews))
          .where((r) => r.toUserId == myId || r.toUserId == 'me')
          .toList(),
    );
    final reviewsCount = myReviews?.length ?? 0;
    final computedRating = (myReviews == null || myReviews.isEmpty)
        ? 0.0
        : myReviews.map((r) => r.rating).reduce((a, b) => a + b) /
            myReviews.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 47.h, 16.w, 8.h),
                child: Text(
                  'Профиль',
                  style: AppText.h1().copyWith(
                    height: 1.21,
                    letterSpacing: 0.40,
                  ),
                ),
              ),
            ),
          ),
          // ── Body ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              children: [
                _ProfileCard(
                  user: user,
                  rating: computedRating,
                  reviewsCount: reviewsCount,
                  onEdit: () => context.push('/profile/edit'),
                ),
                SizedBox(height: 16.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.clipboard_text,
                  label: 'История заказов',
                  onTap: () => context.push('/profile/history'),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  iconAsset: 'assets/images/icon_star_outline.webp',
                  label: 'Отзывы',
                  onTap: () => context.push('/profile/reviews'),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  iconAsset: 'assets/images/icon_support.webp',
                  label: 'Связаться с нами',
                  onTap: () => _showContactSheet(context),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.logout,
                  label: 'Выйти из аккаунта',
                  onTap: () => _confirmLogout(context, ref),
                ),
                SizedBox(height: 8.h),
                _MenuItem(
                  icon: IconsaxPlusLinear.trash,
                  label: 'Удалить аккаунт',
                  onTap: () => _confirmDeleteAccount(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.logout,
                color: AppColors.primary,
                size: 56.r,
              ),
              SizedBox(height: 16.h),
              Text(
                'Вы уверены, что хотите выйти из аккаунта?',
                textAlign: TextAlign.center,
                style: AppText.h3(color: const Color(0xFF111827))
                    .copyWith(height: 1.40),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Column(
                  children: [
                    _LogoutDialogButton(
                      label: 'Выйти',
                      background: AppColors.primary,
                      textColor: Colors.white,
                      onTap: () async {
                        // authRepository.logout() сам зовёт appController + clear authStore.
                        await ref.read(authRepositoryProvider).logout();
                        if (!dialogCtx.mounted) return;
                        Navigator.of(dialogCtx).pop();
                        if (!context.mounted) return;
                        // НЕ на /onboarding: онбординг юзер уже видел,
                        // флаг сохраняется в AppState.logout(). На cold-start
                        // приложение само ведёт сюда же — здесь явно
                        // отправляем туда же, чтобы UX совпадал.
                        context.go('/auth/phone');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _LogoutDialogButton(
                      label: 'Отмена',
                      background: AppColors.surfaceVariant,
                      textColor: const Color(0xFF111827),
                      onTap: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupportSheet(),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    Future<void> doDelete() async {
      // Реальный вызов /api/profile/delete (только если PB подключён).
      // На сервере хук помечает users.deleted_at, переводит активные
      // open/accepted заказы в cancelled, чистит push_tokens и т.д.
      final pb = ref.read(pocketbaseProvider);
      if (pb != null && pb.authStore.isValid) {
        try {
          await http
              .post(
                Uri.parse('${pb.baseURL}/api/profile/delete'),
                headers: {
                  'Authorization': 'Bearer ${pb.authStore.token}',
                  'Content-Type': 'application/json',
                },
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Даже при сетевой ошибке — продолжаем logout (UX-soft).
          // Запрос можно повторить при следующем логине (есть аудит).
        }
      }
      await ref.read(authRepositoryProvider).logout();
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          width: 313.w,
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.trash,
                color: AppColors.primary,
                size: 56.r,
              ),
              SizedBox(height: 16.h),
              Text(
                'Удалить аккаунт?',
                textAlign: TextAlign.center,
                style: AppText.h3(color: const Color(0xFF111827))
                    .copyWith(height: 1.40),
              ),
              SizedBox(height: 8.h),
              Text(
                'Все ваши данные, заказы и отзывы будут безвозвратно удалены',
                textAlign: TextAlign.center,
                style: AppText.body().copyWith(
                  fontSize: 15.sp,
                  color: Colors.black.withValues(alpha: 0.60),
                  height: 1.33,
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Column(
                  children: [
                    _LogoutDialogButton(
                      label: 'Удалить',
                      background: AppColors.primary,
                      textColor: Colors.white,
                      onTap: () async {
                        await doDelete();
                        if (!dialogCtx.mounted) return;
                        Navigator.of(dialogCtx).pop();
                        if (!context.mounted) return;
                        // То же что и при logout — на ввод номера. Онбординг
                        // (как процесс знакомства с приложением) показывать
                        // повторно тому же владельцу устройства нет смысла.
                        // Если устройство сменит владельца — он наберёт свой
                        // номер на /auth/phone, отдельный «онбординг для
                        // нового юзера на этом девайсе» не предусмотрен.
                        context.go('/auth/phone');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _LogoutDialogButton(
                      label: 'Отмена',
                      background: AppColors.surfaceVariant,
                      textColor: const Color(0xFF111827),
                      onTap: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.rating,
    required this.reviewsCount,
    required this.onEdit,
  });
  final AppUser user;
  final double rating;
  final int reviewsCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasTools = user.hasTools;
    final hasTransport = user.hasTransport;
    return AppCard(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Stack(
        children: [
          Column(
            children: [
              _Avatar(photoPath: user.photoPath),
              SizedBox(height: 16.h),
              Text(
                user.name.isEmpty ? 'Пользователь' : user.name,
                textAlign: TextAlign.center,
                style: AppText.h3().copyWith(height: 1.10),
              ),
              if (user.phone.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  user.phone,
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall().copyWith(
                    color: Colors.black.withValues(alpha: 0.60),
                    height: 1.57,
                  ),
                ),
              ],
              Builder(builder: (_) {
                // Собираем только видимые блоки и вставляем 24.w spacer ТОЛЬКО
                // между ними. Trailing-spacer после tools/transport смещал
                // одиночную иконку влево от центра, когда нет рейтинга.
                final blocks = <Widget>[];
                if (hasTools) {
                  blocks.add(Image.asset(
                    'assets/images/icon_tools.png',
                    width: 16.r,
                    height: 16.r,
                  ));
                }
                if (hasTransport) {
                  blocks.add(Image.asset(
                    'assets/images/icon_transport.png',
                    width: 20.r,
                    height: 16.r,
                    // По фигме грузовик тёмный (в отличие от синего ключа).
                    color: AppColors.textPrimary,
                    colorBlendMode: BlendMode.srcIn,
                  ));
                }
                if (reviewsCount > 0) {
                  blocks.add(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/icon_ranking.webp',
                        width: 16.r,
                        height: 16.r,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        rating.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: AppText.bodySmall(weight: FontWeight.w500),
                      ),
                    ],
                  ));
                }
                // Если ни инструмента/транспорта, ни рейтинга — вообще не
                // добавляем ни spacer'а, ни Row. Иначе остаётся «висячий»
                // 4.h перед пустой строкой, и нижний отступ карточки
                // оказывается больше верхнего на эти 4.h.
                if (blocks.isEmpty) return const SizedBox.shrink();
                final children = <Widget>[];
                for (var i = 0; i < blocks.length; i++) {
                  if (i > 0) children.add(SizedBox(width: 24.w));
                  children.add(blocks[i]);
                }
                return Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: children,
                  ),
                );
              }),
            ],
          ),
          Positioned(
            right: 4.w,
            top: -8.h,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: EdgeInsets.all(12.r),
                  child: Image.asset(
                    'assets/images/icon_edit.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoPath});
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    // PB возвращает аватар как URL (http://...), а image_picker — как
    // локальный path. Раньше код всегда звал Image.file — для URL это
    // даёт PathNotFoundException. Разделяем явно.
    final path = photoPath;
    final isUrl = path != null &&
        (path.startsWith('http://') || path.startsWith('https://'));
    final fallback = Center(
      child: Icon(IconsaxPlusLinear.user, size: 64.r, color: AppColors.primary),
    );
    return Container(
      width: 100.r,
      height: 100.r,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? fallback
          : isUrl
              ? AppNetworkImage(url: path, fallback: fallback)
              : Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.icon,
    this.iconAsset,
    required this.label,
    required this.onTap,
  }) : assert(icon != null || iconAsset != null,
            'either icon or iconAsset must be provided');

  final IconData? icon;
  final String? iconAsset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          height: 56.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                SizedBox(
                  width: 24.r,
                  height: 24.r,
                  child: iconAsset != null
                      ? Image.asset(iconAsset!, width: 24.r, height: 24.r)
                      : Icon(icon, color: AppColors.primary, size: 24.r),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.body(weight: FontWeight.w500)
                        .copyWith(height: 1.50),
                  ),
                ),
                SizedBox(width: 16.w),
                Icon(
                  IconsaxPlusLinear.arrow_right_3,
                  color: AppColors.primary,
                  size: 24.r,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutDialogButton extends StatelessWidget {
  const _LogoutDialogButton({
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
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 36.h,
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

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

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
                    'assets/images/icon_support.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Связаться с нами',
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
                  _SupportMessenger(
                    label: 'WhatsApp',
                    asset: 'assets/images/icon_whatsapp.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
                    label: 'Telegram',
                    asset: 'assets/images/icon_telegram.webp',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
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

class _SupportMessenger extends StatelessWidget {
  const _SupportMessenger({
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
