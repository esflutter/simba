import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/messenger_launcher.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart';
import '../../data/remote/pocketbase_client.dart';
import '../reviews/reviews_providers.dart' show reviewsForUserProvider;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// PB realtime-подписка на коллекцию reviews. Без неё, когда другая
  /// сторона завершённого заказа ставит мне отзыв пока я смотрю свой
  /// профиль, рейтинг и счётчик отзывов не сдвигаются до выхода с
  /// экрана и повторного входа.
  Future<void> Function()? _reviewsUnsub;
  String? _subscribedForUserId;
  // Эпоха подписки — инкрементируется на каждый logout/смену юзера.
  // Защищает от гонки: если subscribe(A1) и subscribe(A2) пересекаются
  // во времени (например, два ребилда подряд), завершившийся последним
  // не должен перетереть unsub-токен от того, кто реально активен.
  int _subscribeEpoch = 0;

  // initState не нужен: первая подписка вешается из build при первом
  // появлении user.id (см. условие `_subscribedForUserId != user.id`).
  // Так первая и последующие подписки идут через один и тот же путь.

  Future<void> _subscribeReviews(String myId, int epoch) async {
    if (!mounted) return;
    if (epoch != _subscribeEpoch) return;
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) return;
    if (myId.isEmpty) return;
    try {
      final unsub = await pb.collection('reviews').subscribe('*', (e) {
        if (!mounted) return;
        if (epoch != _subscribeEpoch) return;
        final rec = e.record;
        if (rec == null) {
          ref.invalidate(reviewsForUserProvider(myId));
          return;
        }
        if (rec.getStringValue('to_user') == myId) {
          ref.invalidate(reviewsForUserProvider(myId));
        }
      });
      // Эпоха поменялась пока подписывались — это была подписка от
      // прошлой инкарнации (юзер уже сменился). Откатываем.
      if (!mounted || epoch != _subscribeEpoch) {
        await unsub();
        return;
      }
      _reviewsUnsub = unsub;
    } catch (_) {/* WS недоступен — не критично */}
  }

  Future<void> _cancelSubscription() async {
    final unsub = _reviewsUnsub;
    _reviewsUnsub = null;
    if (unsub != null) await unsub();
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _cancelSubscription();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Подписываемся отдельно на user — иначе ConsumerWidget может пропустить
    // ребилд из-за const-канонизации screens в HomeShell.
    final user = ref.watch(appControllerProvider.select((s) => s.user));
    if (user == null) {
      // Юзер вышел из аккаунта — закрываем подписку, иначе она держит
      // соединение для прошлого id и при следующем визите придут
      // события не того пользователя.
      if (_subscribedForUserId != null) {
        _subscribedForUserId = null;
        _subscribeEpoch++;
        // ignore: discarded_futures
        _cancelSubscription();
      }
      return const Scaffold(body: SizedBox.shrink());
    }
    // Если юзер сменился (logout → login другим аккаунтом, IndexedStack
    // в HomeShell не пересоздаёт ProfileScreen) — переподписываемся на
    // новый id. ВАЖНО: _subscribedForUserId фиксируем синхронно прямо
    // здесь, до postFrame — иначе два подряд build (например, во время
    // загрузки данных) запустят два параллельных subscribe.
    if (_subscribedForUserId != user.id) {
      _subscribedForUserId = user.id;
      // Эпоха инкрементируется на каждую смену юзера — старые подписки,
      // которые ещё в полёте, при возврате увидят рассинхронизацию и
      // откатятся, не перетирая актуальный _reviewsUnsub.
      final epoch = ++_subscribeEpoch;
      // ignore: discarded_futures
      _cancelSubscription();
      final targetId = user.id;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _subscribeReviews(targetId, epoch));
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
                // ── Debug-кнопка отправки тестового пуша ──
                // Видна только в сборке с SHOW_DESIGN_TOGGLES=true.
                // Удобно для разработки: нажал — сам получил пуш на
                // лок-скрин, проверка цепочки клиент → сервер → FCM →
                // Android-уведомление без необходимости двух устройств.
                if (const bool.fromEnvironment(
                  'SHOW_DESIGN_TOGGLES',
                  defaultValue: false,
                )) ...[
                  SizedBox(height: 8.h),
                  _MenuItem(
                    icon: IconsaxPlusLinear.notification,
                    label: 'Тестовый пуш себе',
                    onTap: () => _sendTestPush(context, ref),
                  ),
                ],
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

  /// Дёргает серверный endpoint /api/me/fcm-test (он шлёт пуш текущему
  /// юзеру). Видно только при сборке с SHOW_DESIGN_TOGGLES=true.
  Future<void> _sendTestPush(BuildContext context, WidgetRef ref) async {
    final pb = ref.read(pocketbaseProvider);
    if (pb == null) {
      AppToast.error(context, 'Бэкенд не подключён (mock-режим)');
      return;
    }
    try {
      final res = await pb.send(
        '/api/me/fcm-test',
        method: 'POST',
      ).timeout(const Duration(seconds: 10));
      if (!context.mounted) return;
      // res — Map; sent=true означает что сервер успешно отправил пуш.
      final sent = (res is Map && res['sent'] == true);
      if (sent) {
        AppToast.success(context, 'Пуш отправлен — должен прилететь');
      } else {
        AppToast.error(context, 'Сервер не отправил пуш (нет токена?)');
      }
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Ошибка: $e');
    }
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
            color: AppColors.surface,
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
                style: AppText.h3(color: AppColors.textPrimary)
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
                      textColor: AppColors.surface,
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
                      textColor: AppColors.textPrimary,
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
          // sendWithSharedClient — если сокет shared-клиента закрылся
          // после долгого сна устройства, обёртка пересоздаст клиент.
          // Сам запрос идёт через общий http-клиент, как остальные
          // прямые ручки.
          await sendWithSharedClient(
            (c) => c
                .post(
                  Uri.parse('${pb.baseURL}/api/profile/delete'),
                  headers: {
                    'Authorization': 'Bearer ${pb.authStore.token}',
                    'Content-Type': 'application/json',
                  },
                )
                .timeout(const Duration(seconds: 10)),
          );
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
            color: AppColors.surface,
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
                style: AppText.h3(color: AppColors.textPrimary)
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
                      textColor: AppColors.surface,
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
                      textColor: AppColors.textPrimary,
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
          // width: double.infinity на Column — иначе Stack (loose,
          // alignment=topStart) ужимает колонку до ширины самого широкого
          // ребёнка (обычно это кружок аватарки 100r), и весь блок
          // «аватар + имя + телефон» прижимается к левому краю карточки.
          // На коротких именах («Эльвира») это выглядит как смещение
          // влево от центра — тестировщик так и заметил.
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                _Avatar(photoPath: user.photoPath),
                SizedBox(height: 16.h),
                Text(
                  user.name.isEmpty ? 'Без имени' : user.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.h3().copyWith(height: 1.10),
                ),
                if (user.phone.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    user.phone,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                          formatRating(rating),
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
              ? AppNetworkImage(
                  url: path,
                  width: 100.r,
                  height: 100.r,
                  fallback: fallback,
                )
              : Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  // 100r ≈ 300px на 3×-устройстве; декодить full-res
                  // оригинал (потенциально 1024×1024) под кружок 100lp —
                  // лишние ~4МБ RAM на каждый виджет.
                  cacheWidth: 300,
                  cacheHeight: 300,
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

/// Кнопка диалога logout/удаление с встроенной защитой от двойного тапа.
/// Раньше StatelessWidget без блокировки — второй тап за пол-секунды
/// запускал второй logout/delete параллельно (две отмены push-токенов,
/// гонка навигации). Теперь после первого тапа кнопка дизейблится до
/// завершения onTap, а на время выполнения показывается крутилка вместо
/// текста.
class _LogoutDialogButton extends StatefulWidget {
  const _LogoutDialogButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });
  final String label;
  final Color background;
  final Color textColor;
  // FutureOr — чтобы можно было передать как обычный void callback
  // («Отмена»), так и async-операцию («Выйти», «Удалить»).
  final FutureOr<void> Function() onTap;

  @override
  State<_LogoutDialogButton> createState() => _LogoutDialogButtonState();
}

class _LogoutDialogButtonState extends State<_LogoutDialogButton> {
  bool _busy = false;

  Future<void> _handle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.background,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        // null при _busy — кнопка не реагирует на второй тап.
        onTap: _busy ? null : _handle,
        child: SizedBox(
          width: double.infinity,
          // 48dp — стандартный touch-target Material/Android. Раньше
          // было 36, что меньше рекомендуемого минимума.
          height: 48.h,
          child: Center(
            child: _busy
                ? SizedBox(
                    width: 20.r,
                    height: 20.r,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: widget.textColor,
                    ),
                  )
                : Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.textColor,
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

  /// Открыть мессенджер поддержки. На отказ — тост («WhatsApp / Telegram / MAX
  /// не открылся»). Канал считается «настроенным», если в Env есть
  /// соответствующий идентификатор; иначе кнопка изначально дизейблена,
  /// и сюда мы не попадём.
  Future<void> _open(
    BuildContext sheetContext,
    Future<bool> Function() launcher,
    String labelOnFail,
  ) async {
    final ok = await launcher();
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    if (!ok) {
      AppToast.show(sheetContext, '$labelOnFail не открылся');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Все три кнопки всегда активны. Значения берутся из Env (с
    // placeholder-дефолтами, см. env.dart). Раньше при пустом Env кнопки
    // дизейблились — выглядело как баг, юзер думал «контакты не работают».
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                      color: AppColors.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.29,
                    ),
                  ),
                  const Spacer(),
                  // 44×44 — минимум touch-target для крестика sheet'а.
                  SizedBox(
                    width: 44.r,
                    height: 44.r,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(
                          Icons.close_rounded,
                          color: AppColors.primary,
                          size: 20.r,
                        ),
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
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openWhatsApp(
                        Env.supportWhatsAppPhone,
                      ),
                      'WhatsApp',
                    ),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
                    label: 'Telegram',
                    asset: 'assets/images/icon_telegram.webp',
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openTelegram(
                        username: Env.supportTelegramUsername,
                      ),
                      'Telegram',
                    ),
                  ),
                  SizedBox(width: 28.w),
                  _SupportMessenger(
                    label: 'MAX',
                    asset: 'assets/images/icon_max.webp',
                    onTap: () => _open(
                      context,
                      () => MessengerLauncher.openMax(
                        phone: Env.supportMaxPhone,
                      ),
                      'MAX',
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
              color: AppColors.textPrimary,
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
