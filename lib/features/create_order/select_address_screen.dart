import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/openfreemap_view.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
import '../../data/remote/cities_repository.dart';
import '../../data/remote/dadata_client.dart';
import 'order_draft.dart';

class SelectAddressScreen extends ConsumerStatefulWidget {
  const SelectAddressScreen({super.key});

  @override
  ConsumerState<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SelectAddressScreenState extends ConsumerState<SelectAddressScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final MapController _mapController = MapController();

  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _showSuggestions = false;

  LatLng? _selectedPoint;
  String _selectedAddress = '';
  AddressSuggestion? _selectedSuggestion;

  /// Последнее известное местоположение пользователя — пытаемся подставить
  /// его в качестве стартового центра карты при открытии экрана. Если
  /// разрешение не выдано или координата за пределами поддерживаемых
  /// городов — остаётся `null`, и центр берётся от выбранного города.
  LatLng? _initialFix;

  // ── Race-protection + LRU-кеш для suggest ──────────────────────────
  // Растущий счётчик: каждый новый запрос увеличивает _suggestSeq, и колбэк
  // ответа сравнивает свой mySeq с текущим — устаревшие ответы отбрасываются.
  int _suggestSeq = 0;

  /// Аналогичный счётчик для reverse-geocode в [_onMapTap]. При быстрых
  /// двух тапах по карте ответы DaData могут прийти в произвольном порядке —
  /// поздний ответ затирал результат раннего и UI показывал адрес другой
  /// точки. Поздний обработчик игнорируется, если `mySeq != _mapTapSeq`.
  int _mapTapSeq = 0;
  final Map<String, List<AddressSuggestion>> _suggestCache = {};
  final List<String> _suggestCacheOrder = []; // LRU-порядок (head = oldest)
  static const int _kMaxCacheEntries = 50;

  void _cacheSuggest(String key, List<AddressSuggestion> value) {
    _suggestCache[key] = value;
    _suggestCacheOrder.remove(key);
    _suggestCacheOrder.add(key);
    if (_suggestCacheOrder.length > _kMaxCacheEntries) {
      final oldest = _suggestCacheOrder.removeAt(0);
      _suggestCache.remove(oldest);
    }
  }

  @override
  void initState() {
    super.initState();
    // Если в драфте уже выбран адрес — показываем его как стартовую точку.
    Future.microtask(() {
      final draft = ref.read(orderDraftProvider);
      if (draft.location != null && draft.address.isNotEmpty) {
        setState(() {
          _selectedPoint = draft.location;
          _selectedAddress = draft.address;
          _ctrl.text = draft.address;
          _selectedSuggestion = null; // ранее сохранённый адрес — без свежей подсказки
        });
      }
      // Раньше при пустом поле автоматически проставлялся литерал
      // «Местоположение пользователя» — это выглядит как настоящий
      // адрес, если юзер не очистит, в драфт уходила эта строка как
      // адрес и в публикации висело «Местоположение пользователя».
      // Теперь оставляем поле пустым, hint «Введите адрес или выберите
      // на карте» сам по себе достаточно понятен.
    });
    // В приоритете — фактическое местоположение пользователя. Берём только
    // уже закэшированный fix, без запроса разрешения: если permission
    // выдан — последняя известная координата приходит мгновенно; если нет
    // — оставляем дефолт «центр выбранного города».
    _bootstrapInitialFix();
  }

  Future<void> _bootstrapInitialFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !mounted) return;
      final userPoint = LatLng(pos.latitude, pos.longitude);
      // Подставляем местоположение, только если оно попадает в радиус
      // одного из поддерживаемых городов. Иначе пользователь может
      // оказаться где-нибудь в командировке — там карта бессмысленна
      // (в этом городе не работаем), привычнее показать центр того
      // города, который выбран в чипе сверху.
      final citiesAsync = ref.read(citiesProvider);
      final cities = citiesAsync.maybeWhen(
        data: (v) => v,
        orElse: () => MockData.cities,
      );
      final inAnyCity = cities.any((c) {
        final meters = Geolocator.distanceBetween(
          c.center.latitude,
          c.center.longitude,
          userPoint.latitude,
          userPoint.longitude,
        );
        return meters / 1000.0 <= c.boundsRadiusKm;
      });
      if (!inAnyCity) return;
      setState(() => _initialFix = userPoint);
    } catch (_) {/* нет GPS / сервис выключен — молча игнорим */}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Ключ LRU-кеша подсказок. Включает FIAS города, чтобы после смены
  /// города не отдавать подсказки из предыдущего (старые записи в кеше
  /// относились бы к другому DaData-locations-фильтру).
  String _cacheKey(String query) {
    final city = ref.read(appControllerProvider).selectedCity;
    return '${city.dadataFiasId ?? city.name}:$query';
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      // Меньше 3 символов — DaData всё равно не даёт осмысленных подсказок,
      // экономим запросы и не дёргаем сеть.
      setState(() {
        _suggestions = const [];
        _showSuggestions = trimmed.isNotEmpty ? _showSuggestions : false;
        _loading = false;
      });
      return;
    }
    // Если query уже в LRU — показываем мгновенно, без сетевого запроса.
    final key = _cacheKey(trimmed);
    final cached = _suggestCache[key];
    if (cached != null) {
      _suggestCacheOrder
        ..remove(key)
        ..add(key);
      setState(() {
        _suggestions = cached;
        _showSuggestions = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _showSuggestions = true;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 300), _runSuggest);
  }

  Future<void> _runSuggest() async {
    final query = _ctrl.text.trim();
    if (query.length < 3) return;
    final key = _cacheKey(query);
    // Двойная проверка кеша: пока тикал debounce, могло прилететь дубль-значение.
    final cached = _suggestCache[key];
    if (cached != null) {
      _suggestCacheOrder
        ..remove(key)
        ..add(key);
      if (!mounted) return;
      setState(() {
        _suggestions = cached;
        _loading = false;
      });
      return;
    }
    final mySeq = ++_suggestSeq;
    final client = ref.read(dadataClientProvider);
    final city = ref.read(appControllerProvider).selectedCity;
    // city.dadataFiasId — строгое ограничение DaData на выбранный город.
    // restrictToCity=true → DaData физически не вернёт адреса других городов.
    // cityName используется как fallback на старых записях без FIAS-ID
    // (если миграция 1700000009 ещё не отработала на бэке).
    try {
      final results = await client.suggest(
        query,
        count: 7,
        cityFiasId: city.dadataFiasId,
        cityName: city.dadataFiasId == null ? city.name : null,
      );
      // Игнорируем устаревшие ответы: пока летел запрос, юзер мог продолжить
      // печатать, и пришёл уже более новый mySeq.
      if (mySeq != _suggestSeq || !mounted) return;
      _cacheSuggest(key, results);
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    } catch (_) {
      // Сетевая ошибка / DaData недоступна — без catch _loading зависал
      // в true навсегда, и юзер видел крутящийся спиннер пока не наберёт
      // следующий символ. Тихо схлопываем подсказки в пустой результат —
      // юзер может ввести адрес вручную или ткнуть в карту.
      if (mySeq != _suggestSeq || !mounted) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
    }
  }

  void _pickSuggestion(AddressSuggestion s) {
    // Подсказка без координат (новостройка и т.п.): НЕ затираем уже
    // выбранную на карте точку/адрес — иначе кнопка «Выбрать» молча гаснет
    // (canSubmit требует _selectedPoint), и сделанный выбор теряется без
    // объяснения. Закрываем список и просим уточнить дом / выбрать на карте.
    if (s.point == null) {
      setState(() {
        _showSuggestions = false;
        _suggestions = const [];
      });
      FocusScope.of(context).unfocus();
      AppToast.show(context, 'Уточните дом или выберите точку на карте');
      return;
    }
    setState(() {
      _selectedAddress = s.value;
      _selectedPoint = s.point;
      _selectedSuggestion = s;
      _ctrl.text = s.value;
      _showSuggestions = false;
      _suggestions = const [];
    });
    FocusScope.of(context).unfocus();
    _mapController.move(s.point!, 16);
  }

  Future<void> _onMapTap(LatLng point) async {
    final city = ref.read(appControllerProvider).selectedCity;

    // Phase 1 — дешёвый локальный radius-чек. Отсекает явные промахи
    // (юзер из Москвы тапнул куда-то в Сибирь) БЕЗ запроса в DaData,
    // экономит квоту и время. boundsRadiusKm * 1.5 — мягкий буфер,
    // точная FIAS-сверка идёт в Phase 2.
    final centerDistance = const Distance().as(LengthUnit.Kilometer, point, city.center);
    if (centerDistance > city.boundsRadiusKm * 1.5) {
      if (!mounted) return;
      AppToast.show(context, 'В ${city.name} мы пока не работаем здесь');
      return;
    }

    // Сохраняем предыдущее состояние, чтобы откатиться при провале Phase 2
    // (reverse-geocode не вернул FIAS — заказ без верифицированного города
    // публиковать нельзя).
    final prevPoint = _selectedPoint;
    final prevAddress = _selectedAddress;
    final prevSuggestion = _selectedSuggestion;
    final prevText = _ctrl.text;

    // Race-protection. До seq-счётчика при двух быстрых тапах поздний
    // ответ DaData затирал точку, выбранную вторым тапом, координатами
    // первого. Теперь устаревший ответ просто отбрасывается.
    final mySeq = ++_mapTapSeq;

    setState(() {
      _selectedPoint = point;
      _selectedAddress = 'Точка на карте';
      _selectedSuggestion = null;
      _ctrl.text = '';
      _showSuggestions = false;
    });

    // Phase 2 — DaData reverse-geocode для точной FIAS-сверки.
    // Параллельно даёт красивый текст адреса для UI.
    final result = await ref.read(dadataClientProvider).geolocate(point);
    // Опоздавший ответ для уже отменённого тапа — игнорируем целиком,
    // даже если бы он был успешным: позже его перепишет актуальный.
    if (mySeq != _mapTapSeq || !mounted) return;

    // Fail-closed: НЕТ FIAS → нет адреса. DaData не вернула ничего (сеть/лес/
    // пустырь) или вернула без cityFiasId — откатываем выбор маркера и просим
    // юзера попробовать снова или выбрать из подсказок. Раньше тут был
    // «мягкий» проход — заказ доходил до summary с cityFiasId == null и
    // обходил FIAS-guard.
    if (result == null ||
        result.cityFiasId == null ||
        result.cityFiasId!.isEmpty) {
      setState(() {
        _selectedPoint = prevPoint;
        _selectedAddress = prevAddress;
        _selectedSuggestion = prevSuggestion;
        _ctrl.text = prevText;
      });
      AppToast.show(
        context,
        'Не удалось определить адрес. Попробуйте ещё раз или выберите из подсказок',
      );
      return;
    }

    if (city.dadataFiasId != null &&
        result.cityFiasId != city.dadataFiasId) {
      // Точка реально вне выбранного города (например, Подмосковье вместо
      // Москвы). Откатываем выбор и предупреждаем юзера.
      setState(() {
        _selectedPoint = prevPoint;
        _selectedAddress = prevAddress;
        _selectedSuggestion = prevSuggestion;
        _ctrl.text = prevText;
      });
      AppToast.show(context, 'В ${city.name} мы пока не работаем здесь');
      return;
    }
    setState(() {
      _selectedAddress = result.value;
      _selectedSuggestion = result;
      _ctrl.text = result.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    // .select — иначе экран с активной картой и подсказками ребилдится
    // на любую мутацию AppState (createOrder, addReview, setRole и т.д.).
    final city = ref.watch(
      appControllerProvider.select((s) => s.selectedCity),
    );
    // Приоритет центра карты: ранее выбранная точка → известное
    // местоположение пользователя (если попадает в один из городов из
    // списка) → центр выбранного в чипе города.
    final initialCenter = _selectedPoint ?? _initialFix ?? city.center;
    // Если стартуем от пользовательской точки или ранее выбранного адреса
    // — зум более «уличный» (15), чтобы было видно дома. Для центра
    // целого города оставляем 13 — обзор района вокруг центра.
    final initialZoom =
        (_selectedPoint != null || _initialFix != null) ? 15.0 : 13.0;
    final canSubmit = _selectedPoint != null && _selectedAddress.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ──
          Container(
            color: AppColors.surface,
            child: Column(
              children: [
                SizedBox(height: 4.h),
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: const Color(0x4C3C3C43),
                      borderRadius: BorderRadius.circular(2.5.r),
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                SizedBox(
                  height: 36.h,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: Text(
                          'Адрес',
                          style: AppText.bodyLarge(weight: FontWeight.w600)
                              .copyWith(letterSpacing: -0.43, height: 1.29),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: const AppBackButton(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: _SearchField(
              controller: _ctrl,
              onChanged: _onQueryChanged,
              onClear: () {
                setState(() {
                  _ctrl.clear();
                  _suggestions = const [];
                  _showSuggestions = false;
                });
              },
              onFocus: () {
                if (_ctrl.text.isNotEmpty) {
                  setState(() => _showSuggestions = true);
                }
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // ── Карта OpenFreeMap ──
                // Зум-кнопки и «моё местоположение» теперь рисует сам
                // OpenFreeMapView — единый стиль с лентой заказов.
                // При тапе на «моё местоположение» виджет сам определяет
                // координату и плавно туда едет; адрес мы подхватываем в
                // onMyLocationTap через reverse-geocode (см. `_onMapTap`).
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16.h),
                    child: _MapWithCenterPin(
                      controller: _mapController,
                      initialCenter: initialCenter,
                      initialZoom: initialZoom,
                      marker: _selectedPoint,
                      onTap: _onMapTap,
                      onMyLocation: _onMapTap,
                    ),
                  ),
                ),
                // ── Подсказки ──
                if (_showSuggestions)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4.h,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: _SuggestionsList(
                        loading: _loading,
                        items: _suggestions,
                        onPick: _pickSuggestion,
                        empty: !Env.hasPocketbase
                            // Тех-сообщение «бэкенд не настроен / run_dev.bat»
                            // имеет смысл только разработчику — в release
                            // показываем пользовательский текст.
                            ? (kDebugMode
                                ? 'Подсказки недоступны: бэкенд не настроен. Запустите через run_dev.bat'
                                : 'Не удалось загрузить подсказки. Попробуйте позже.')
                            : (!_loading && _ctrl.text.trim().isNotEmpty &&
                                    _suggestions.isEmpty
                                ? 'Ничего не найдено. Попробуйте указать точнее или выбрать точку на карте'
                                : null),
                      ),
                    ),
                  ),
                // ── Кнопка «Выбрать» ──
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: PrimaryButton(
                        label: 'Выбрать',
                        height: 50.h,
                        onPressed: canSubmit
                            ? () {
                                final s = _selectedSuggestion;
                                // Если адрес выбран свежей подсказкой/реверс-геокодом —
                                // сохраняем структурные поля. Если юзер оставил
                                // ранее сохранённый адрес из драфта (s == null) — не
                                // затираем лежащие в драфте FIAS/КЛАДР: передаём только
                                // address/location (метаполя останутся прежними благодаря
                                // copyWith).
                                ref.read(orderDraftProvider.notifier).update(
                                      location: _selectedPoint!,
                                      address: _selectedAddress.trim(),
                                      addressFiasId: s?.fiasId,
                                      addressKladrId: s?.kladrId,
                                      cityFiasId: s?.cityFiasId,
                                      postalCode: s?.postalCode,
                                      qcGeo: s?.qcGeo,
                                    );
                                context.pop();
                              }
                            : null,
                      ),
                    ),
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

class _MapWithCenterPin extends StatelessWidget {
  const _MapWithCenterPin({
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.marker,
    required this.onTap,
    required this.onMyLocation,
  });

  final MapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final LatLng? marker;
  final void Function(LatLng) onTap;
  final void Function(LatLng) onMyLocation;

  @override
  Widget build(BuildContext context) {
    return OpenFreeMapView(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      mapController: controller,
      onMapTap: onTap,
      showZoomControls: true,
      showMyLocation: true,
      onMyLocationTap: onMyLocation,
      // «Выбрать» (50h) + вертикальные паддинги (16+16) ≈ 82h. С учётом
      // safe-area внизу выходит примерно столько и нужно, чтобы кнопки
      // зума и геолокации центрировались между поисковой строкой
      // и верхней границей кнопки «Выбрать», а не уезжали под неё.
      controlsBottomInset: 82.h + MediaQuery.of(context).padding.bottom,
      markers: marker == null
          ? const []
          : [
              OpenFreeMapMarker(
                id: 'selected',
                point: marker!,
              ),
            ],
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({
    required this.loading,
    required this.items,
    required this.onPick,
    this.empty,
  });

  final bool loading;
  final List<AddressSuggestion> items;
  final ValueChanged<AddressSuggestion> onPick;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: Material(
        color: AppColors.surface,
        elevation: 4,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 280.h),
          child: loading && items.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  child: const Center(
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
              : items.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Text(
                        empty ?? 'Начните вводить адрес…',
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (_, i) {
                        final s = items[i];
                        return InkWell(
                          onTap: () => onPick(s),
                          child: SizedBox(
                            height: 56.h,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20.w),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  s.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFocus,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFocus;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
      if (_focus.hasFocus) widget.onFocus();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Container(
        height: 56.h,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
        child: Row(
          children: [
            Icon(IconsaxPlusLinear.search_normal_1,
                size: 24.r, color: AppColors.textPrimary),
            SizedBox(width: 16.w),
            Expanded(
              child: TextField(
                focusNode: _focus,
                controller: widget.controller,
                onChanged: widget.onChanged,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: AppColors.primary,
                style: AppText.body(color: AppColors.textPrimary)
                    .copyWith(height: 1.50),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  counterText: '',
                  hintText: 'Введите адрес или выберите на карте',
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: widget.onClear,
                  behavior: HitTestBehavior.opaque,
                  // 44×44 тап-зона при визуально том же 24-размером
                  // крестике. Раньше «голая» иконка часто не реагировала,
                  // пользователю приходилось стирать вручную.
                  child: SizedBox(
                    width: 44.r,
                    height: 44.r,
                    child: Icon(
                      IconsaxPlusLinear.close_circle,
                      size: 24.r,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
