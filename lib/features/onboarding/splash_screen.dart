import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Бутстрап с двумя гарантиями:
  ///   1) Splash показывается минимум 1.2 с (UX: пользователь успевает
  ///      увидеть бренд, не получает «вспышку»).
  ///   2) Если в authStore есть сохранённый токен — дожидаемся authRefresh
  ///      (≤3 с) ДО навигации, иначе при холодном старте с валидным токеном
  ///      пользователь видел бы экран онбординга на доли секунды.
  Future<void> _bootstrap() async {
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 1200));
    try {
      // 6 секунд: на медленной 3G/2G refresh не успевал за 3с, пользователь
      // оставался без сессии и логинился заново при каждом старте. 6с —
      // компромисс между «не зависнуть на splash» и «дать токену дойти».
      await ref
          .read(authRepositoryProvider)
          .tryRefreshAuth()
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
    } catch (_) {
      // Любая ошибка refresh не блокирует переход — пойдём по
      // обычному ветвлению onboarding (state.user может быть null).
    }
    await minSplash;
    if (!mounted) return;
    _go();
  }

  void _go() {
    if (!mounted) return;
    final state = ref.read(appControllerProvider);
    final next = nextOnboardingRoute(state);
    if (next != null) {
      context.go(next);
      return;
    }
    final tab = state.role == UserRole.customer ? 'my' : 'orders';
    context.go('/home/$tab');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.primarySplash,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primarySplash,
        body: Column(
          children: [
            const Spacer(flex: 3),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Image.asset(
                'assets/images/logo_handshake.webp',
                width: double.infinity,
                height: 244.h,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 26.h),
            Text('SimbA', style: AppText.splashTitle),
            const Spacer(flex: 2),
            SizedBox(
              width: 44.r,
              height: 44.r,
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 48.h),
          ],
        ),
      ),
    );
  }
}
