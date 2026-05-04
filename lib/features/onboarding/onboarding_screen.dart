import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class _OnboardPage {
  const _OnboardPage({
    required this.image,
    required this.title,
    required this.body,
  });
  final String image;
  final String title;
  final String body;
}

const List<_OnboardPage> _pages = [
  _OnboardPage(
    image: 'assets/images/onboard_1.webp',
    title: 'SimbA',
    body:
        'SimbA — название приложения происходит от слова Simbios (симбиоз) — взаимовыгодное существование. Всегда есть человек, которому нужна помощь, и есть человек, готовый эту помощь оказать.',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_2.webp',
    title: 'SimbA найдёт разовую работу под твои возможности',
    body:
        'Тебе 14+ и копишь на мечту: смартфон, велосипед, планшет и т.д.? Есть желание самостоятельно зарабатывать чтобы не просить деньги у мамы с папой?',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_3.webp',
    title: 'SimbA поможет найти любую подработку. Деньги сразу',
    body:
        'Тебе 18+, ты студент на очном отделении. Срочно нужны деньги, но не хочешь занимать у друзей? Сложно совмещать работу с учёбой?',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_4.webp',
    title:
        'SimbA поможет найти исполнителя рядом, который почистит снег, нарубит дрова, выкосит траву и т.д.',
    body:
        'Вам 20–40 лет, живёте, работаете в городе и ввиду занятости не можете часто приезжать к своим родителям далеко от Вас? Но желаете помогать чаще, чтобы близкие чувствовали Вашу заботу.',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_5.webp',
    title: 'SimbA поможет найти исполнителя рядом, который сделает за Вас рутинную работу',
    body:
        'Вам 40–60 лет, Вы состоятельный бизнесмен, высокооплачиваемый специалист? Ваше время стоит дорого? Хотите жить в своё удовольствие и не тратить время на такие вещи как уборка дома, чистка снега, стрижка газона и т.д.?',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      context.go('/city');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageView(page: _pages[i]),
              ),
              Positioned(
                right: 24.w,
                bottom: 16.h,
                child: _NextRoundButton(onTap: _next),
              ),
              Positioned(
                left: 24.w,
                bottom: 32.h,
                child: _Indicator(count: _pages.length, index: _index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});
  final _OnboardPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // ratio: img section 414/812 ≈ 51%, txt occupies the rest with paddings
        final imgH = constraints.maxHeight * 0.50;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: imgH,
              child: Center(
                child: Image.asset(
                  page.image,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 96.h),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        style: AppText.h2(color: AppColors.textOnPrimary),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        page.body,
                        style: AppText.body(color: AppColors.textOnPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.only(right: 6.w),
          width: active ? 22.w : 8.w,
          height: 8.h,
          decoration: BoxDecoration(
            color: active
                ? AppColors.textOnPrimary
                : AppColors.textOnPrimary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8.r),
          ),
        );
      }),
    );
  }
}

class _NextRoundButton extends StatelessWidget {
  const _NextRoundButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 64.r,
          height: 64.r,
          alignment: Alignment.center,
          child: Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 26.r),
        ),
      ),
    );
  }
}
