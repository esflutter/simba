import 'dart:async';

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

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), _go);
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
