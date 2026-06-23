import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';

class RolePickerScreen extends ConsumerStatefulWidget {
  const RolePickerScreen({super.key});

  @override
  ConsumerState<RolePickerScreen> createState() => _RolePickerScreenState();
}

class _RolePickerScreenState extends ConsumerState<RolePickerScreen> {
  // Защита от двойного тапа. Картинка-герой делит экран на левую и
  // правую половину поверх двух карточек снизу — итого 4 кликабельные
  // зоны. Без блокировки два быстрых тапа стартуют два setRole + два
  // фоновых syncExecutorStatus (каждый просит GPS-координаты), а
  // markOnboardingSeen вообще успевает отработать дважды.
  bool _busy = false;

  Future<void> _finishRegistration(UserRole role, String homePath) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(appControllerProvider.notifier);
      notifier.setRole(role);
      // Регистрация полностью завершена — теперь онбординг считается
      // «просмотренным» (флаг хранится в prefs пожизненно). Раньше
      // он ставился в конце страниц онбординга, и если юзер не доходил
      // до конца регистрации, на следующий запуск приложение могло
      // привести его в неконсистентное состояние.
      await notifier.markOnboardingSeen();
      if (!mounted) return;
      context.go(homePath);
    } finally {
      // Сбрасываем _busy в `finally` — иначе при исключении в
      // markOnboardingSeen (например, prefs не доступны) экран
      // замёрз бы навсегда без визуальной подсказки.
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pickCustomer() {
    _finishRegistration(UserRole.customer, '/home/create');
  }

  void _pickExecutor() {
    _finishRegistration(UserRole.executor, '/home/orders');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: const Alignment(0, 0.5),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/role_hero.webp',
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned.fill(
                          child: Row(
                            children: [
                              Expanded(
                                flex: 42,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _pickCustomer,
                                ),
                              ),
                              const Spacer(flex: 16),
                              Expanded(
                                flex: 42,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _pickExecutor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoleCard(
                    title: 'Нужна помощь',
                    subtitle: 'Разместить заказ на услугу',
                    onTap: _pickCustomer,
                  ),
                  SizedBox(height: 8.h),
                  _RoleCard(
                    title: 'Готов помочь',
                    subtitle: 'Найти заказ на услугу',
                    onTap: _pickExecutor,
                  ),
                  SizedBox(height: 66.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      padding: EdgeInsets.only(top: 16.h, left: 24.w, right: 24.w, bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: AppText.h4(color: AppColors.primary),
          ),
          SizedBox(height: 12.h),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$subtitle ',
                  style: AppText.body(color: Colors.black.withValues(alpha: 0.60))
                      .copyWith(height: 1.39),
                ),
                // Webp-стрелка из Figma вместо текстового символа '→' —
                // тот же ассет, что в карточке заказа.
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Image.asset(
                    'assets/images/icon_arrow_forward.webp',
                    width: 18.r,
                    height: 18.r,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
