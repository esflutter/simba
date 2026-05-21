import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/system_bar_style.dart';

// ─── Допустимые размеры заголовка ───────────────────────────────────────
//
// Заказчик попросил два варианта на сравнение: +2 ступени (32sp) и
// +3 ступени (36sp) от исходного h2 24sp. Переключаются debug-кнопкой
// слева сверху на первой странице, ровно туда-сюда между двумя
// значениями. Применяется и в старой, и в новой версии онбординга —
// чтобы заказчик видел, как крупный «SimbA» смотрится в любой раскладке.
// На страницах 2–5 размер заголовка всегда 24sp (фиксированный h2),
// переключателя там нет — заголовки длинные, крупнее им не нужно.
const double _kTitleSizePlus2 = 32;
const double _kTitleSizePlus3 = 36;

class _OnboardPage {
  const _OnboardPage({
    required this.imageOld,
    required this.imageNew,
    required this.title,
    required this.body,
  });
  // Ассет для «старого» макета (картинка занимает верхние 50% экрана через
  // BoxFit.cover). Это оригинальные onboard_N.webp с зашитым синим фоном —
  // дизайн до правок.
  final String imageOld;
  // Ассет для «нового» макета (картинка по центру, BoxFit.contain). Здесь
  // прозрачные версии: на первой странице — logo_handshake.webp (как на
  // сплешке), на страницах 2–5 — onboard_N_new.webp с обрезанными
  // прозрачными полями (центр фигуры = центр файла).
  final String imageNew;
  final String title;
  final String body;
}

const List<_OnboardPage> _pages = [
  _OnboardPage(
    imageOld: 'assets/images/onboard_1.webp',
    imageNew: 'assets/images/logo_handshake.webp',
    title: 'SimbA',
    // Перед каждым тире стоит неразрывный пробел ( ) — тогда строка
    // никогда не начнётся с тире, оно всегда «приклеено» к предыдущему
    // слову при автопереносе. \n после «существование.» сохраняем как
    // в фигме — явный перенос перед «Всегда».
    body:
        'SimbA – название приложения происходит от слова Simbios (симбиоз) – взаимовыгодное существование. \nВсегда есть человек, которому нужна помощь и есть человек, готовый эту помощь оказать.',
  ),
  _OnboardPage(
    imageOld: 'assets/images/onboard_2.webp',
    imageNew: 'assets/images/onboard_2_new.webp',
    title: 'SimbA найдёт разовую работу под твои возможности',
    body:
        'Тебе 14+ и копишь на мечту: смартфон, велосипед, планшет и т.д.? Есть желание самостоятельно зарабатывать, чтобы не просить деньги у мамы с папой?',
  ),
  _OnboardPage(
    imageOld: 'assets/images/onboard_3.webp',
    imageNew: 'assets/images/onboard_3_new.webp',
    title: 'SimbA поможет найти любую подработку. Деньги сразу',
    body:
        'Тебе 18+, ты студент на очном отделении. Срочно нужны деньги, но не хочешь занимать у друзей? Сложно совмещать работу с учёбой?',
  ),
  _OnboardPage(
    imageOld: 'assets/images/onboard_4.webp',
    imageNew: 'assets/images/onboard_4_new.webp',
    title:
        'SimbA поможет найти исполнителя рядом, который почистит снег, нарубит дрова, выкосит траву и т.д.',
    body:
        'Вам 20–40 лет, живёте, работаете в городе и ввиду занятости не можете часто приезжать к своим родителям далеко от Вас? Но желаете помогать чаще, чтобы близкие чувствовали Вашу заботу?',
  ),
  _OnboardPage(
    imageOld: 'assets/images/onboard_5.webp',
    imageNew: 'assets/images/onboard_5_new.webp',
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
  // Какую версию онбординга показывать. false — «новая» (картинка по
  // центру, прозрачные ассеты), true — «старая» (картинка сверху 50%
  // c BoxFit.cover, точно как было до правок). Переключается debug-кнопкой
  // справа сверху, есть на всех страницах.
  bool _useOldLayout = false;
  // Размер заголовка «SimbA» на первой странице. Переключается
  // debug-кнопкой слева сверху между двумя значениями: 32 и 36.
  double _titleSize = _kTitleSizePlus2;

  @override
  void initState() {
    super.initState();
    _initCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  void _toggleLayout() {
    setState(() => _useOldLayout = !_useOldLayout);
  }

  void _toggleTitleSize() {
    setState(() {
      _titleSize = _titleSize == _kTitleSizePlus2
          ? _kTitleSizePlus3
          : _kTitleSizePlus2;
    });
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
      // Раньше тут вызывался markOnboardingSeen — после первого
      // долистывания страниц онбординг считался «просмотренным».
      // Но если пользователь не доходил до конца регистрации
      // (закрывал на экране города/телефона), на следующий запуск
      // онбординг не показывался, а флоу обрывался посередине.
      // Теперь флаг «просмотрен» ставится в конце регистрации
      // (см. role_picker_screen), а здесь просто переходим к городу.
      context.go('/city');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: simbaSystemBarStyle(
        navBarColor: AppColors.primary,
        navIconBrightness: Brightness.light,
        statusIconBrightness: Brightness.light,
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
                  isFirstPage: i == 0,
                  useOldLayout: _useOldLayout,
                  // На первой странице — переключаемый 32/36 (debug-кнопка).
                  // На страницах 2–5 — фиксированный 20sp (h3, на ступень
                  // меньше старого h2 24sp): заголовки там длинные, и более
                  // компактный кегль помогает им красивее ложиться в строки
                  // без дёрганых переносов.
                  titleSize: i == 0 ? _titleSize : 20,
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

              // ── Debug-тогглеры дизайна ──
              // Видны ТОЛЬКО в debug-сборке, рисуются поверх PageView и
              // кнопки-стрелки. В release не попадают в дерево виджетов.
              //   Справа сверху — переключатель макета (Старая ⇄ Новая
              //   версия), есть на всех страницах.
              //   Слева сверху — переключатель размера заголовка
              //   (32 ⇄ 36 sp), есть только на первой странице.
              //   На 2–5 заголовки длинные, размер фиксированный 24sp.
              if (kDebugMode) ...[
                Positioned(
                  right: 16.w,
                  top: 16.h,
                  child: _VariantToggle(
                    icon: Icons.swap_horiz_rounded,
                    onTap: _toggleLayout,
                  ),
                ),
                if (_index == 0)
                  Positioned(
                    left: 16.w,
                    top: 16.h,
                    child: _VariantToggle(
                      icon: Icons.format_size_rounded,
                      onTap: _toggleTitleSize,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({
    required this.page,
    required this.index,
    required this.ctrl,
    required this.isFirstPage,
    required this.useOldLayout,
    required this.titleSize,
  });
  final _OnboardPage page;
  final int index;
  final PageController ctrl;
  final bool isFirstPage;
  // Какой макет рендерить.
  final bool useOldLayout;
  // Размер заголовка в sp. На стр 1 переключаем циклом 24/32/36, на 2–5
  // всегда 24.
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return useOldLayout
            ? _buildOldLayout(context, constraints)
            : _buildNewLayout(context, constraints);
      },
    );
  }

  /// «Старая» версия онбординга — точно как было до правок дизайна:
  /// картинка занимает верхние 50% экрана через BoxFit.cover на полную
  /// ширину, под ней заголовок (h2 w700) и описание (body 16sp) с
  /// выравниванием влево. Шрифты — исходные. Картинки — оригинальные
  /// onboard_N.webp с зашитым синим фоном (page.imageOld).
  /// Анимация свайпа — параллакс через _ParallaxFade, эмблема без
  /// параллакса (двигается только с PageView).
  Widget _buildOldLayout(BuildContext context, BoxConstraints constraints) {
    final imgH = constraints.maxHeight * 0.50;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: imgH,
          child: Image.asset(
            page.imageOld,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
          child: _ParallaxFade(
            ctrl: ctrl,
            index: index,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      style: AppText.h2(color: AppColors.textOnPrimary).copyWith(
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        // Размер берём из titleSize — родитель подставляет
                        // 32/36 для первой страницы (через тогглер) и
                        // 20sp для страниц 2–5 (h3, на ступень меньше).
                        fontSize: titleSize.sp,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      page.body,
                      style: AppText.body(color: AppColors.textOnPrimary)
                          .copyWith(height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// «Новая» версия онбординга: заголовок сверху по центру, эмблема
  /// СТРОГО в центре экрана, описание внизу слева. Картинки — прозрачные
  /// (page.imageNew). Подходит и для длинных заголовков, и для коротких,
  /// потому что эмблема не «уезжает» в зависимости от длины текста.
  Widget _buildNewLayout(BuildContext context, BoxConstraints constraints) {
    // Резерв снизу под круглую кнопку-стрелку (Positioned right:16,
    // bottom:16, сама 64×64). Эту зону Padding'ом отрезаем от полезной
    // области, чтобы эмблема не центрировалась с её учётом и не
    // «съезжала» относительно того, что глаз видит как центр.
    final bottomReserve = 96.h;
    // Верхний резерв для заголовка — учитывает место под debug-тогглеры
    // в углах сверху, чтобы заголовок «SimbA» не наезжал на них.
    final topPad = 56.h;
    return Stack(
      children: [
        // ── Эмблема: ровно по центру полезной вертикальной зоны
        // (вся SafeArea минус резерв под кнопку-стрелку снизу). БЕЗ
        // параллакса — двигается только с PageView, как в исходной
        // версии онбординга. ──
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomReserve),
            child: Center(child: _buildEmblem(constraints)),
          ),
        ),
        // ── Заголовок: прикреплён к верху с фиксированным отступом
        // topPad, по центру по горизонтали, с параллаксом при свайпе. ──
        Positioned(
          top: topPad,
          left: 16.w,
          right: 16.w,
          child: _ParallaxFade(
            ctrl: ctrl,
            index: index,
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              style: AppText.h2(color: AppColors.textOnPrimary).copyWith(
                fontSize: titleSize.sp,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ),
        // ── Описание: прикреплено к низу с отступом bottomReserve,
        // выравнивание влево, на 1 ступень мельче (14sp), с параллаксом. ──
        Positioned(
          bottom: bottomReserve,
          left: 16.w,
          right: 16.w,
          child: _ParallaxFade(
            ctrl: ctrl,
            index: index,
            child: Text(
              page.body,
              textAlign: TextAlign.start,
              style: AppText.bodySmall(color: AppColors.textOnPrimary)
                  .copyWith(height: 1.45),
            ),
          ),
        ),
      ],
    );
  }

  /// Эмблема для нового макета. Размер — ~45% высоты экрана с clamp
  /// 240–360dp. Файл прозрачный, его центр совпадает с центром фигуры
  /// (после обрезки прозрачных полей), поэтому BoxFit.contain в квадратном
  /// Box даёт центрированную фигуру без перекосов.
  Widget _buildEmblem(BoxConstraints constraints) {
    final imageSize = (constraints.maxHeight * 0.45).clamp(240.0, 360.0);
    return Image.asset(
      page.imageNew,
      width: imageSize,
      height: imageSize,
      fit: BoxFit.contain,
    );
  }
}

/// Параллакс-обёртка: дополнительный Transform.translate + Opacity
/// поверх PageView. Текст внутри уходит/появляется быстрее, чем
/// картинка страницы, — это и есть «фирменная» анимация исходного
/// онбординга. Применяется ТОЛЬКО к текстовым блокам; эмблема в новом
/// макете двигается без этого ускорения.
class _ParallaxFade extends StatelessWidget {
  const _ParallaxFade({
    required this.ctrl,
    required this.index,
    required this.child,
  });
  final PageController ctrl;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return AnimatedBuilder(
      animation: ctrl,
      child: child,
      builder: (context, child) {
        final p = ctrl.hasClients
            ? (ctrl.page ?? index.toDouble())
            : index.toDouble();
        final offset = p - index;
        final opacity = (1 - offset.abs()).clamp(0.0, 1.0);
        // Asymmetric fade: уходящая страница исчезает быстрее (квадрат),
        // входящая — линейно. Сохраняет ритм исходной анимации.
        final asymOpacity = offset < 0
            ? (opacity * opacity).clamp(0.0, 1.0)
            : opacity.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(offset * screenW, 0),
          child: Opacity(opacity: asymOpacity, child: child),
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
    // Внешняя дуга-прогресс 64×64. Внутренняя картинка чуть меньше 56,
    // потому что в webp у самого белого круга есть лёгкий outer-padding —
    // если рендерить 56×56, визуально круг почти упирается в дугу.
    // 52.r даёт честные ~4 пикселя зазора по фигме.
    final arcSize = 64.r;
    final btnSize = 52.r;
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
      // Webp `icon_arrow_forward_button.webp` — целый кнопочный круг из
      // Figma (белая заливка + синяя стрелка). Material остаётся прозрачным,
      // InkWell даёт ripple поверх.
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: btnSize,
            height: btnSize,
            child: Image.asset(
              'assets/images/icon_arrow_forward_button.webp',
              fit: BoxFit.contain,
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
      ..color = AppColors.surface
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

/// Debug-кнопка переключения варианта дизайна. Видна ТОЛЬКО в
/// debug-сборке: в release родительский `if (kDebugMode)` отбрасывает
/// её из дерева виджетов, продакшн чистый.
///
/// Универсальная — назначение задаётся иконкой и onTap из родителя:
///   Icons.swap_horiz_rounded → Старая ⇄ Новая версия, есть на всех
///     страницах справа сверху.
///   Icons.format_size_rounded → размер заголовка 32 ⇄ 36, только на
///     первой странице слева сверху.
///
/// Форма — небольшой круг 44×44 с полупрозрачной заливкой, чтобы не
/// мешать просмотру дизайна и при этом всегда был под рукой.
class _VariantToggle extends StatelessWidget {
  const _VariantToggle({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = 44.r;
    return Material(
      color: Colors.white.withValues(alpha: 0.20),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: AppColors.surface, size: 22.r),
        ),
      ),
    );
  }
}
