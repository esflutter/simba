import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/mock/app_state.dart';

class _OnboardPage {
  const _OnboardPage({required this.image, required this.title, required this.body});
  final String image;
  final String title;
  final String body;
}

const List<_OnboardPage> _pages = [
  _OnboardPage(
    image: 'assets/images/onboard_1.webp',
    title: 'SimbA',
    // Перед каждым тире стоит неразрывный пробел ( ) — тогда строка
    // никогда не начнётся с тире, оно всегда «приклеено» к предыдущему
    // слову при автопереносе. \n после «существование.» сохраняем как
    // в фигме — явный перенос перед «Всегда».
    body:
        'SimbA – название приложения происходит от слова Simbios (симбиоз) – взаимовыгодное существование. \nВсегда есть человек, которому нужна помощь и есть человек, готовый эту помощь оказать.',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_2.webp',
    title: 'SimbA найдёт разовую работу под твои возможности',
    body:
        'Тебе 14+ и копишь на мечту: смартфон, велосипед, планшет и т.д.? Есть желание самостоятельно зарабатывать, чтобы не просить деньги у мамы с папой?',
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
        'Вам 20–40 лет, живёте, работаете в городе и ввиду занятости не можете часто приезжать к своим родителям далеко от Вас? Но желаете помогать чаще, чтобы близкие чувствовали Вашу заботу?',
  ),
  _OnboardPage(
    image: 'assets/images/onboard_5.webp',
    title: 'SimbA поможет найти исполнителя рядом, который сделает за Вас рутинную работу',
    body:
        'Вам 40–60 лет, Вы состоятельный бизнесмен, высокооплачиваемый специалист? Ваше время стоит дорого? Хотите жить в своё удовольствие и не тратить время на такие вещи как уборка дома, чистка снега, стрижка газона и т.д.?',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PageController();
  late final AnimationController _initCtrl;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _initCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _initCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 308), curve: Curves.easeOut);
    } else {
      // Помечаем онбординг как пройденный — повторно не покажется даже
      // после logout (флаг хранится в prefs как «свойство устройства»).
      // Дожидаемся записи в prefs перед навигацией — иначе при cold restart
      // прямо после онбординга юзер увидит его повторно.
      () async {
        await ref.read(appControllerProvider.notifier).markOnboardingSeen();
        if (!mounted) return;
        context.go('/city');
      }();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Stack(
            children: [
              // ── Full-screen swipeable PageView ──
              PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageContent(
                  page: _pages[i],
                  index: i,
                  ctrl: _ctrl,
                ),
              ),

              // ── Button with arc progress (overlay) ──
              Positioned(
                right: 16.w,
                bottom: 16.h,
                child: _NextRoundButton(
                  onTap: _next,
                  ctrl: _ctrl,
                  initCtrl: _initCtrl,
                  count: _pages.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, required this.index, required this.ctrl});
  final _OnboardPage page;
  final int index;
  final PageController ctrl;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgH = constraints.maxHeight * 0.50;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: imgH,
              child: Image.asset(page.image, width: double.infinity, fit: BoxFit.cover),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (context, child) {
                  final p = ctrl.hasClients ? (ctrl.page ?? index.toDouble()) : index.toDouble();
                  final offset = p - index;
                  final opacity = (1 - offset.abs()).clamp(0.0, 1.0);
                  // Asymmetric fade: exits fast (quadratic), enters linearly
                  final asymOpacity = offset < 0
                      ? (opacity * opacity).clamp(0.0, 1.0)
                      : opacity.clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(offset * screenW, 0),
                    child: Opacity(opacity: asymOpacity, child: child),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          page.title,
                          style: AppText.h2(color: AppColors.textOnPrimary)
                              .copyWith(height: 1.1, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 10.h),
                        Text(
                          page.body,
                          style: AppText.body(color: AppColors.textOnPrimary).copyWith(height: 1.5),
                        ),
                      ],
                    ),
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

class _NextRoundButton extends StatelessWidget {
  const _NextRoundButton({
    required this.onTap,
    required this.ctrl,
    required this.initCtrl,
    required this.count,
  });
  final VoidCallback onTap;
  final PageController ctrl;
  final AnimationController initCtrl;
  final int count;

  @override
  Widget build(BuildContext context) {
    final arcSize = 72.r;
    final btnSize = 56.r;
    return AnimatedBuilder(
      animation: Listenable.merge([ctrl, initCtrl]),
      builder: (context, child) {
        final page = ctrl.hasClients ? (ctrl.page ?? 0.0) : 0.0;
        final easedInit = CurvedAnimation(parent: initCtrl, curve: Curves.easeOut).value;
        final progress = ((page + easedInit) / count).clamp(0.0, 1.0);
        return SizedBox(
          width: arcSize,
          height: arcSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(arcSize, arcSize),
                painter: _ArcPainter(progress: progress),
              ),
              child!,
            ],
          ),
        );
      },
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: btnSize,
            height: btnSize,
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.primary,
              size: 26.r,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 1.5;
    final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}
