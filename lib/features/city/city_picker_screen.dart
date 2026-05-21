import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../core/router/app_router.dart' show nextOnboardingRoute;
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/remote/cities_repository.dart';
import '../../data/remote/pocketbase_client.dart';

// Города-миллионники России по убыванию населения.
// TODO(P2): после миграции переехать на флаг `is_million_plus` в коллекции
// cities (или отдельную view) — сейчас хардкод, потому что seed/миграция
// такого поля не предоставляет.
const _millionCityIds = [
  'msk', 'spb', 'nsk', 'ekb', 'kzn', 'nn', 'krs',
  'chl', 'sam', 'ufa', 'rnd', 'omk', 'krd', 'vrn',
  'prm', 'vlg',
];

class CityPickerScreen extends ConsumerStatefulWidget {
  const CityPickerScreen({super.key});

  @override
  ConsumerState<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends ConsumerState<CityPickerScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;
  String _query = '';
  String? _selectedId;
  bool _searching = false;

  /// Список городов: из PocketBase (если бэкенд подключён) либо из моков.
  /// `citiesProvider` сам делает fallback на моки при ошибке сети.
  List<City> _citiesFrom(AsyncValue<List<City>> async) {
    final list = async.maybeWhen(
      data: (xs) => xs,
      orElse: () => MockData.cities,
    );
    return list.where((c) => _millionCityIds.contains(c.id)).toList();
  }

  List<City> _filter(List<City> all) => _query.isEmpty
      ? all
      : all
          .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    // В режиме смены города (пользователь уже создан) сразу разворачиваем
    // экран в режим поиска с пустым полем и полным списком городов —
    // синхронно в initState, чтобы не было «вспышки» шапки на первом кадре.
    final hasUser = ref.read(appControllerProvider).user != null;
    if (hasUser) {
      _searching = true;
      _animCtrl.value = 1.0;
    }
  }

  void _onFieldTap() {
    if (!_searching) {
      setState(() => _searching = true);
      _animCtrl.forward();
    }
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    if (_selectedId == null) _searchCtrl.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    _animCtrl.reverse();
  }

  /// Куда уйти после того, как юзер с уже созданным аккаунтом выбрал
  /// город. Раньше тут был просто `context.pop()` — но если /city был
  /// первым экраном в стеке (например, юзер ранее закрыл приложение
  /// на этапе заполнения профиля и его перебросило на выбор города
  /// при следующем cold-start), pop ничего не делал, и юзер залипал
  /// на экране — казалось, что города «не нажимаются».
  ///
  /// Если pop возможен — pop'аем (это смена города из настроек или
  /// дип-линка). Если нет — догоняем следующий шаг онбординга через
  /// `nextOnboardingRoute`; если все шаги пройдены, ведём на главный.
  void _goAfterCityChosen() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final state = ref.read(appControllerProvider);
    final next = nextOnboardingRoute(state);
    context.go(next ?? '/home/my');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedId != null;
    final allCities = _citiesFrom(ref.watch(citiesProvider));
    final filtered = _filter(allCities);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Шапка: скрывается при поиске ──
            SizeTransition(
              axisAlignment: 1,
              sizeFactor: ReverseAnimation(_anim),
              child: FadeTransition(
                opacity: ReverseAnimation(_anim),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 70.h, 16.w, 0),
                  child: Column(
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/icon_location.webp',
                          width: 80.r,
                          height: 80.r,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Text(
                        'Укажите город',
                        textAlign: TextAlign.center,
                        style: AppText.h2().copyWith(letterSpacing: -0.10),
                      ),
                      SizedBox(height: 9.h),
                      Text(
                        'Покажем предложения и исполнителей в вашем городе',
                        textAlign: TextAlign.center,
                        style: AppText.body().copyWith(
                          color: Colors.black.withValues(alpha: 0.60),
                          height: 1.38,
                        ),
                      ),
                      SizedBox(height: 28.h),
                    ],
                  ),
                ),
              ),
            ),

            // ── Строка поиска: кнопка «назад» + поле ──
            AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: _anim.value * 8.h),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          heightFactor: _anim.value,
                          child: Opacity(
                            opacity: _anim.value,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                final hasUser =
                                    ref.read(appControllerProvider).user !=
                                        null;
                                if (hasUser && context.canPop()) {
                                  context.pop();
                                } else {
                                  _closeSearch();
                                }
                              },
                              // Минимальный тап-таргет 44×44. Раньше иконка 20.r
                              // была без расширения, попадание с первого раза
                              // сбивалось — особенно сразу после клавиатуры,
                              // когда экран сжат.
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 4.h),
                                child: SizedBox(
                                  width: 44.r,
                                  height: 44.r,
                                  // Center — без него иконка 20.r рисуется в
                                  // верхнем-левом углу 44×44 контейнера, и
                                  // визуально стрелка съезжает с прежней
                                  // позиции дизайна.
                                  child: Center(
                                    child: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 20.r,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                );
              },
              child: AppTextField(
                label: 'Город или населённый пункт',
                controller: _searchCtrl,
                onTap: _onFieldTap,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                onChanged: (v) => setState(() {
                  if (!_searching) {
                    _searching = true;
                    _animCtrl.forward();
                  }
                  _query = v;
                  _selectedId = null;
                }),
              ),
            ),

            // ── Список городов: появляется снизу ──
            Expanded(
              child: FadeTransition(
                opacity: _anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(_anim),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
                    child: filtered.isEmpty
                        ? Padding(
                            padding: EdgeInsets.only(bottom: 16.h),
                            child: _NoCityFound(
                                onRequest: () => _showRequestSheet(context)),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.only(bottom: 16.h),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                SizedBox(height: 8.h),
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              final selected = c.id == _selectedId;
                              return Material(
                                color: selected
                                    ? AppColors.primarySoft
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(16.r),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16.r),
                                  onTap: () {
                                    final ctrl = ref
                                        .read(appControllerProvider.notifier);
                                    final hasUser = ref
                                            .read(appControllerProvider)
                                            .user !=
                                        null;
                                    // Режим смены города (юзер уже создан) —
                                    // сохраняем выбор и сразу возвращаемся.
                                    // `setCity` сам сбрасывает адресные поля
                                    // draft'а через `orderDraftProvider.notifier.clearAddress()`
                                    // — здесь повторный вызов не нужен.
                                    if (hasUser) {
                                      ctrl.setCity(c.id);
                                      _goAfterCityChosen();
                                      return;
                                    }
                                    _searchCtrl.text = c.name;
                                    setState(() => _selectedId = c.id);
                                    _closeSearch();
                                  },
                                  child: SizedBox(
                                    height: 48.h,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 16.w),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              c.name,
                                              style: AppText.body()
                                                  .copyWith(height: 1.50),
                                            ),
                                          ),
                                          if (selected)
                                            Icon(
                                              IconsaxPlusLinear.tick_circle,
                                              color: AppColors.primary,
                                              size: 22.r,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),

            // ── Кнопка «Далее» ──
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: (_searching && !canContinue)
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                      child: PrimaryButton(
                        label: 'Далее',
                        onPressed: canContinue
                            ? () {
                                final ctrl = ref
                                    .read(appControllerProvider.notifier);
                                final hasUser = ref
                                        .read(appControllerProvider)
                                        .user !=
                                    null;
                                ctrl.setCity(_selectedId!);
                                if (hasUser) {
                                  _goAfterCityChosen();
                                } else {
                                  context.go('/auth/phone');
                                }
                              }
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRequestSheet(BuildContext context) async {
    final submitted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (_) => _RequestCitySheet(initialName: _query),
    );
    if (!context.mounted || submitted == null || submitted.isEmpty) return;
    // Заявка на новый город уходит в коллекцию city_requests (public-create
    // правило в миграции). Если PB недоступен — fire-and-forget, юзеру всё
    // равно показываем «спасибо», т.к. он не должен страдать от наших
    // backend-проблем. Поля схемы: name (required), user (optional),
    // status (required, заполняется хуком в 'new'), ip (заполняется хуком).
    final pb = ref.read(pocketbaseProvider);
    if (pb != null) {
      unawaited(() async {
        try {
          await pb.collection('city_requests').create(body: {
            // schema-имя поля — name (раньше слали city_name → бэк отвергал).
            'name': submitted.trim(),
            if (pb.authStore.record?.id.isNotEmpty == true)
              'user': pb.authStore.record!.id,
          }).timeout(const Duration(seconds: 10));
        } catch (_) {/* swallow — заявка некритична для дальнейшего флоу */}
      }());
    }
    // Для пользователей, меняющих город из «Заказов», страница уже открыта в
    // режиме поиска — не сворачиваем её в шапку «Укажите город», чтобы они
    // могли продолжить искать. Сбрасываем только текст и фокус.
    final hasUser = ref.read(appControllerProvider).user != null;
    if (hasUser) {
      FocusScope.of(context).unfocus();
      _searchCtrl.clear();
      setState(() {
        _query = '';
        _selectedId = null;
      });
    } else {
      _closeSearch();
    }
    AppToast.show(context, 'Заявка отправлена. Спасибо!');
  }
}


class _NoCityFound extends StatelessWidget {
  const _NoCityFound({required this.onRequest});
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset(
              'assets/images/icon_location.webp',
              width: 80.r,
              height: 80.r,
            ),
          ),
          SizedBox(height: 24.h),
          // Единый стиль empty-state (как «Нет активных заказов» в ленте
          // и «Нет отзывов»): 20/w600/-0.45 заголовок + 17/w400/-0.40
          // подзаголовок при alpha 60%. Раньше тут стоял h2 как у шапки
          // — типографика выпадала из стиля остальных empty-state'ов.
          Text(
            'Города пока нет в списке',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: -0.45,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Оставьте заявку — добавим ваш населённый пункт',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.60),
              fontSize: 17.sp,
              fontWeight: FontWeight.w400,
              height: 1.29,
              letterSpacing: -0.40,
            ),
          ),
          SizedBox(height: 28.h),
          PrimaryButton(label: 'Оставить заявку', onPressed: onRequest),
        ],
      ),
    );
  }
}

class _RequestCitySheet extends StatefulWidget {
  const _RequestCitySheet({this.initialName = ''});

  final String initialName;

  @override
  State<_RequestCitySheet> createState() => _RequestCitySheetState();
}

class _RequestCitySheetState extends State<_RequestCitySheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialName);
  bool get _enabled => _ctrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16.w,
          16.h,
          16.w,
          MediaQuery.viewInsetsOf(context).bottom + 16.h,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text('Заявка на добавление города', style: AppText.h4()),
          SizedBox(height: 16.h),
          AppTextField(
            label: 'Название города',
            controller: _ctrl,
            onChanged: (_) => setState(() {}),
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
          ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Отправить',
            onPressed: _enabled
                ? () => Navigator.of(context).pop(_ctrl.text.trim())
                : null,
          ),
          ],
        ),
      ),
    );
  }
}
