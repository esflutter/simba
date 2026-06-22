import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/primary_button.dart';

/// Гейт действий для гостевого режима (App Store 5.1.1).
///
/// Возвращает `true`, если пользователь авторизован — действие можно
/// выполнять. Если гость — показывает мягкий лист входа и возвращает `false`.
/// Звать в начале КАЖДОГО действия, недоступного гостю: откликнуться,
/// создать заказ, открыть карточку/контакт, переключить роль, табы
/// «Создать/Мои/Профиль» и т.п.
bool requireAuth(BuildContext context, WidgetRef ref, {String? reason}) {
  final user = ref.read(appControllerProvider).user;
  if (user != null) return true;
  showLoginGate(context, reason: reason);
  return false;
}

/// Мягкий лист входа: «Войдите, чтобы …» с кнопками «Войти» и «Позже».
/// «Войти» открывает экран входа в режиме гейта (закрываемый, см. 5.5).
/// «Позже» просто закрывает лист — гость остаётся в ленте.
Future<void> showLoginGate(BuildContext context, {String? reason}) async {
  final goLogin = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => _LoginGateSheet(reason: reason),
  );
  if (goLogin == true && context.mounted) {
    // gate=1 → экран входа становится закрываемым и после входа возвращает
    // в ленту, а не на дефолтный /home/my.
    context.push('/auth/phone?gate=1');
  }
}

class _LoginGateSheet extends StatelessWidget {
  const _LoginGateSheet({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final title =
        reason == null ? 'Войдите, чтобы продолжить' : 'Войдите, чтобы $reason';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppText.h2().copyWith(letterSpacing: -0.10),
              ),
              SizedBox(height: 8.h),
              Text(
                'Для этого действия нужен вход по номеру телефона.',
                textAlign: TextAlign.center,
                style: AppText.body().copyWith(
                  color: Colors.black.withValues(alpha: 0.60),
                  height: 1.38,
                ),
              ),
              SizedBox(height: 24.h),
              PrimaryButton(
                label: 'Войти',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              SizedBox(height: 8.h),
              SecondaryButton(
                label: 'Позже',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
