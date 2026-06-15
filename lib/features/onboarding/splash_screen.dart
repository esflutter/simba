import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/system_bar_style.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/auth_repository.dart';
import '../../data/remote/push_handler.dart';

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

  /// Бутстрап:
  ///   1) Минимальное время сплэша — 500 мс, только чтобы не было резкой
  ///      «вспышки» при моментальной навигации. Раньше держали 1.2 с
  ///      ради «брендирования», но это превращалось в искусственную
  ///      задержку при каждом запуске даже когда токен мгновенный.
  ///   2) Таймаут refresh — 3 с (раньше 6 с). Reality-check: если за
  ///      три секунды бэк не ответил, пользователю всё равно лучше
  ///      попасть на /auth/phone и попробовать заново, чем сидеть на
  ///      сплэше до 6 с. Refresh-запрос продолжит работать в фоне —
  ///      ничего не «теряется».
  Future<void> _bootstrap() async {
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await ref
          .read(authRepositoryProvider)
          .tryRefreshAuth()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
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
    // Если по тапу на пуш обработчик уже увёл нас с заставки на нужный
    // экран (deep-link при холодном старте — push_handler через
    // scheduleMicrotask), НЕ перетираем его переходом на главную: go()
    // заменяет весь стек, и открытый по ссылке заказ исчез бы.
    if (GoRouterState.of(context).uri.toString() != '/splash') return;
    final state = ref.read(appControllerProvider);
    final next = nextOnboardingRoute(state);
    if (next != null) {
      context.go(next);
      return;
    }
    final tab = state.role == UserRole.customer ? 'my' : 'orders';
    context.go('/home/$tab');
    // Если приложение открыли тапом по пушу при холодном старте — применяем
    // отложенную глубокую ссылку ПОВЕРХ главной (стек: главная → заказ),
    // чтобы «назад» вёл на главную, а не на заставку. Если ничего не
    // отложено — no-op.
    ref.read(pushHandlerProvider).applyPendingColdStart();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: simbaSystemBarStyle(
        navBarColor: AppColors.primarySplash,
        navIconBrightness: Brightness.light,
        statusIconBrightness: Brightness.light,
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
                // Декодируем под фактическую высоту, а не полный размер
                // исходника (~1100px) — иначе на старте в памяти висит
                // лишний крупный битмап.
                cacheHeight:
                    (244.h * MediaQuery.of(context).devicePixelRatio).round(),
              ),
            ),
            SizedBox(height: 26.h),
            Text('SimbA', style: AppText.splashTitle),
            const Spacer(flex: 2),
            SizedBox(
              width: 44.r,
              height: 44.r,
              child: const CircularProgressIndicator(
                color: AppColors.surface,
                strokeWidth: 4,
              ),
            ),
            SizedBox(height: 48.h),
          ],
        ),
      ),
    );
  }
}
