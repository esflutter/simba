import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/location_permission.dart';

/// Скрываем государственные границы (тонкие линии между странами и
/// регионами) — для приложения они визуальный шум, пользователи смотрят
/// на маркеры заказов. В positron слои-границы имеют id вида
/// `boundary_2/3/disputed` и в JSON стиле живут в `source-layer:
/// "boundary"`. Фильтруем И по id, И по `tileSource` — оба нужны:
/// у некоторых слоёв id может быть префиксован ThemeReader'ом, и
/// строковое совпадение по id не всегда срабатывает.
vtr.Theme _hideAdminBoundaries(vtr.Theme src) {
  return vtr.Theme(
    id: src.id,
    version: src.version,
    layers: src.layers.where((vtr.ThemeLayer l) {
      final String id = l.id.toLowerCase();
      final String? source = l.tileSource?.toLowerCase();
      if (source == 'boundary') return false;
      if (id.contains('boundary')) return false;
      if (id.contains('admin')) return false;
      return true;
    }).toList(growable: false),
  );
}

/// Лимит дискового кэша тайлов OpenFreeMap. 200 МБ — это ~2–3 тысячи
/// уже посещённых тайлов; пакет `vector_map_tiles` сам выкидывает
/// самые старые при превышении (LRU). Хранятся в Application Cache
/// Directory — ОС может его очистить при нехватке места, что нас
/// устраивает (потеря карты не страшна).
const int _kTileCacheMaxSizeBytes = 200 * 1024 * 1024;

/// Сколько хранить тайл, прежде чем перепросить его у OpenFreeMap.
/// 30 дней — компромисс: тайлы OSM обновляются раз в неделю-две, но
/// для маркетплейса услуг свежесть карты не критична. Зато заметно
/// меньше трафика при повторных открытиях.
const Duration _kTileCacheTtl = Duration(days: 30);

/// Папка кэша внутри system app cache. Изолированная директория, чтобы
/// случайно не зацепить чужие файлы при ручной чистке.
Future<Directory> _resolveTilesCacheFolder() async {
  final Directory base = await getApplicationCacheDirectory();
  final Directory dir = Directory('${base.path}/openfreemap_tiles');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Маркер на OpenFreeMap карте. Цвет зависит от статуса заказа:
/// красный — открыт, оранжевый — есть отклики/принят, зелёный — завершён.
class OpenFreeMapMarker {
  const OpenFreeMapMarker({
    required this.id,
    required this.point,
    this.color = AppColors.markerRed,
  });

  final String id;
  final LatLng point;
  final Color color;
}

/// Плавный переход камеры к точке/зуму вместо моментального `move()`.
///
/// flutter_map не умеет анимировать камеру сам — стандартное
/// `MapController.move()` ставит камеру на новое значение в один кадр.
/// При свайпе между маркерами это выглядит как «прыжок», и пользователь
/// теряет ориентацию: какой маркер был, какой стал.
///
/// Помогает классический паттерн: `AnimationController` тикает 0..1
/// за 400 мс с `easeInOut`, на каждом тике линейно интерполируем
/// lat/lng/zoom между стартовой и целевой точкой и зовём `move()`.
/// Контроллер диспозим в `addStatusListener` по `completed`, чтобы не
/// течь.
extension AnimatedMapMove on MapController {
  void animatedMove(
    LatLng dest,
    double destZoom, {
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 400),
  }) {
    final LatLng startCenter;
    final double startZoom;
    try {
      startCenter = camera.center;
      startZoom = camera.zoom;
    } catch (_) {
      // Камера ещё не готова (карта не отрисована) — пропускаем
      // анимацию, иначе словим NoCameraException на первом кадре.
      return;
    }
    final AnimationController ctrl =
        AnimationController(duration: duration, vsync: vsync);
    final CurvedAnimation anim =
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);
    bool disposed = false;
    void disposeOnce() {
      if (disposed) return;
      disposed = true;
      anim.dispose();
      ctrl.dispose();
    }
    ctrl.addListener(() {
      final double t = anim.value;
      move(
        LatLng(
          startCenter.latitude +
              (dest.latitude - startCenter.latitude) * t,
          startCenter.longitude +
              (dest.longitude - startCenter.longitude) * t,
        ),
        startZoom + (destZoom - startZoom) * t,
      );
    });
    anim.addStatusListener((AnimationStatus s) {
      // completed/dismissed — нормальное завершение; обработка обоих важна
      // потому что при быстрых повторных тапах кнопок зума предыдущая
      // анимация прерывается «dismissed» и без этого хука контроллер
      // оставался бы в памяти до GC.
      if (s == AnimationStatus.completed ||
          s == AnimationStatus.dismissed) {
        disposeOnce();
      }
    });
    ctrl.forward();
  }
}

/// Карта на основе OpenFreeMap (бесплатные векторные тайлы OSM).
///
/// Атрибуция «© OpenStreetMap © OpenMapTiles» обязательна по лицензии
/// и рисуется в правом нижнем углу.
///
/// Стиль кэшируется в State, а не в статике: при повторном открытии
/// экрана создаётся новый State и стиль перечитывается. Это отказ от
/// микро-оптимизации в обмен на корректность — иначе один сетевой сбой
/// «травил» бы кэш до перезапуска приложения.
class OpenFreeMapView extends StatefulWidget {
  const OpenFreeMapView({
    super.key,
    this.markers = const <OpenFreeMapMarker>[],
    this.initialCenter,
    this.initialZoom = 12,
    this.onMarkerTap,
    this.onMapTap,
    this.interactive = true,
    this.styleUri = 'https://tiles.openfreemap.org/styles/positron',
    this.mapController,
    this.selectedMarkerId,
    this.showZoomControls = false,
    this.showMyLocation = false,
    this.onMyLocationTap,
    this.controlsBottomInset = 0,
  });

  final List<OpenFreeMapMarker> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;
  final void Function(LatLng point)? onMapTap;

  /// Если `false` — карта статичная (для read-only превью адреса заказа
  /// в деталях). Жесты pan/zoom/double-tap отключены, кнопки управления
  /// тоже не показываются.
  final bool interactive;
  final String styleUri;

  /// Внешний контроллер для программного управления центром/зумом
  /// (например, при выборе адреса из подсказки или анимации к маркеру).
  /// Если не передан — создаётся внутренний.
  final MapController? mapController;

  /// Если передан, маркер с этим id рисуется крупнее и с более
  /// выраженной тенью — для синхронизации с выбранной карточкой
  /// (например, активный заказ в списке на карте).
  final String? selectedMarkerId;

  /// Показывать встроенные кнопки `+`/`-` зума справа над атрибуцией.
  /// На экране `select_address` зум-кнопки рисует сам экран рядом
  /// с кнопкой «моё местоположение», поэтому по умолчанию выключено.
  final bool showZoomControls;

  /// Показывать синюю точку «моё местоположение» (в стиле Google Maps)
  /// и кнопку под зумом, которая центрирует карту на ней. Включается
  /// только на тех экранах, где это уместно (каталог заказов на карте).
  /// Если у пользователя не выдано разрешение на геолокацию, точка
  /// не отрисовывается, кнопка остаётся — тап по ней инициирует
  /// запрос разрешения.
  final bool showMyLocation;

  /// Колбэк после успешного тапа кнопки «моё местоположение». Срабатывает
  /// уже после того, как координата определена, — родитель может, например,
  /// запустить реверс-геокод и подставить адрес (как на экране выбора
  /// адреса заказа) или просто скрыть нижнюю карточку (как в ленте).
  final ValueChanged<LatLng>? onMyLocationTap;

  /// Нижний инсет для кнопок управления картой. Используется, когда снизу
  /// поверх карты лежит другой UI (например, плавающая кнопка «Выбрать»
  /// на экране адреса) — тогда вертикальный центр для +/− и геолокации
  /// считаем не от низа карты, а от верхней границы этого блока.
  final double controlsBottomInset;

  @override
  State<OpenFreeMapView> createState() => _OpenFreeMapViewState();
}

class _OpenFreeMapViewState extends State<OpenFreeMapView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Future<Style> _styleFuture;
  late final MapController _internalController;

  /// Текущее местоположение пользователя — обновляется стримом
  /// `Geolocator.getPositionStream`. `null`, пока не пришёл первый
  /// fix или если разрешение не выдано.
  LatLng? _myLocation;
  StreamSubscription<Position>? _positionSub;

  /// Запоминаем, был ли стрим активен ДО ухода в background — чтобы
  /// при возврате (`resumed`) пересоздать его, не дожидаясь действия
  /// пользователя. Раньше подписка жила всё время, что съедало батарею
  /// у активных исполнителей, оставивших приложение свёрнутым.
  bool _wasStreamingBeforePause = false;

  MapController get _controller =>
      widget.mapController ?? _internalController;

  /// Загружаем стиль OpenFreeMap, но темы (text-field) подменяем
  /// нашей версией с метками только на русском. Оригинал нужен ради
  /// провайдеров тайлов и спрайтов — там абсолютные URL OpenFreeMap,
  /// и их безопаснее взять из готовой `StyleReader`. Тему собираем из
  /// локального ассета `assets/maps/positron.json`, где у каждого
  /// `text-field` оставлен только `name:ru` с откатом на `name`
  /// (для мест без русского имени — например, мелких сёл за рубежом).
  Future<Style> _loadLocalizedStyle() async {
    // Под VPN / нестабильным каналом первая попытка StyleReader может
    // упасть (TLS handshake таймаут, DNS-флап). Раньше карта в этом
    // случае показывалась серой — мы вообще не обрабатывали ошибку.
    // Теперь делаем 3 попытки с растущей задержкой и явным таймаутом
    // на каждую — на стабильной сети это занимает первые ~300 мс, на
    // флапающей даём шанс ~12 секунд суммарно.
    Style? original;
    Object? lastError;
    const delays = [
      Duration.zero,
      Duration(milliseconds: 700),
      Duration(seconds: 2),
    ];
    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
        if (!mounted) {
          throw StateError('widget disposed during style retry');
        }
      }
      try {
        original = await StyleReader(uri: widget.styleUri)
            .read()
            .timeout(const Duration(seconds: 8));
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (original == null) {
      // Все три попытки упали — пробрасываем ошибку наверх. UI поймает
      // её в FutureBuilder и покажет дружелюбное сообщение вместо
      // серого фона. Карта попробует загрузиться при следующем заходе
      // на экран — стиль не кэшируется в памяти процесса.
      throw lastError ?? Exception('map style unreachable');
    }
    try {
      final String text =
          await rootBundle.loadString('assets/maps/positron.json');
      final dynamic parsed = await compute(jsonDecode, text);
      if (parsed is! Map<String, dynamic>) return original;
      final vtr.Theme ruTheme = vtr.ThemeReader().read(parsed);
      return Style(
        name: original.name,
        theme: ruTheme,
        providers: original.providers,
        sprites: original.sprites,
        center: original.center,
        zoom: original.zoom,
      );
    } catch (_) {
      // Если локальный JSON битый/отсутствует — карта рендерится
      // с оригинальным стилем (двуязычные метки), но не падает.
      return original;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _internalController = MapController();
    _styleFuture = _loadLocalizedStyle();
    if (widget.showMyLocation) {
      _bootstrapMyLocation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Когда приложение свёрнуто, держать GPS-стрим не имеет смысла:
    // никто не видит карту, а батарея течёт. Останавливаем поток на
    // paused/inactive и пересоздаём при возврате в resumed — но только
    // если он работал до сворачивания (нет лишней инициализации, если
    // юзер ни разу не нажимал «моё местоположение»).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_positionSub != null) {
        _wasStreamingBeforePause = true;
        _positionSub?.cancel();
        _positionSub = null;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasStreamingBeforePause && widget.showMyLocation && mounted) {
        _wasStreamingBeforePause = false;
        _bootstrapMyLocation();
      }
    }
  }

  @override
  void didUpdateWidget(covariant OpenFreeMapView old) {
    super.didUpdateWidget(old);
    if (old.styleUri != widget.styleUri) {
      _styleFuture = _loadLocalizedStyle();
    }
    // Включили showMyLocation после первоначального построения —
    // подписываемся на стрим, если permission уже выдан.
    if (widget.showMyLocation && !old.showMyLocation) {
      _bootstrapMyLocation();
    }
    if (!widget.showMyLocation && old.showMyLocation) {
      _positionSub?.cancel();
      _positionSub = null;
      _myLocation = null;
    }
    // Если родитель сменил центр (типичный сценарий — пользователь
    // переключил город в чипе сверху, оставаясь на вкладке «карта») —
    // плавно перецентрируем камеру. Без этого карта оставалась бы на
    // прежнем городе, пока её вручную не подвинут.
    final LatLng? newCenter = widget.initialCenter;
    final LatLng? oldCenter = old.initialCenter;
    final bool centerChanged = newCenter != null &&
        (oldCenter == null ||
            oldCenter.latitude != newCenter.latitude ||
            oldCenter.longitude != newCenter.longitude);
    if (centerChanged) {
      // PostFrame — чтобы дождаться, пока камера прорисуется и
      // `animatedMove` не упал в NoCameraException.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _controller.animatedMove(
            newCenter,
            widget.initialZoom,
            vsync: this,
          );
        } catch (_) {/* карта ещё не готова */}
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    // Внутренний MapController нужно явно диспозить — иначе flutter_map
    // держит ссылки на стримы движений камеры, и каждое открытие
    // карты (feed, выбор адреса, детали) утекает в RAM. Внешний
    // контроллер не трогаем — за него отвечает родитель.
    _internalController.dispose();
    super.dispose();
  }

  /// Если разрешение на геолокацию уже выдано — сразу подписываемся
  /// на стрим. Если нет — ничего не делаем; пользователь тапнет
  /// кнопку «моё местоположение» и тогда мы запросим permission.
  Future<void> _bootstrapMyLocation() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return;
    final LocationPermission perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      return;
    }
    _startPositionStream();
  }

  void _startPositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        // 5 м точности достаточно для отображения «синей точки» и
        // не сажает батарею; обновления чаще раза в 2-3 сек не нужны.
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position p) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(p.latitude, p.longitude));
    }, onError: (_) {/* silent — нет сети, GPS недоступен */});
  }

  /// Тап по кнопке «моё местоположение». Если permission ещё нет —
  /// запрашиваем; при успехе стартуем стрим и центрируем карту на
  /// первом fix'е (или на текущем, если он уже есть).
  Future<void> _onMyLocationTap() async {
    final bool granted = await ensureLocationPermission();
    if (!granted || !mounted) return;
    if (_positionSub == null) _startPositionStream();
    LatLng? target = _myLocation;
    target ??= await _waitForFix();
    if (target == null || !mounted) return;
    try {
      _controller.animatedMove(target, 15, vsync: this);
    } catch (_) {/* карта не готова */}
    // Колбэк — после того, как фактическая координата определена, чтобы
    // родителю можно было передать её (например, для реверс-геокода).
    widget.onMyLocationTap?.call(target);
  }

  /// Ждём первый fix до 4 секунд. Используется при первом тапе кнопки,
  /// когда стрим только что запустился и `_myLocation` ещё пуст.
  /// Проверка `mounted` в цикле обязательна: если виджет ушёл с экрана
  /// за эти 4 секунды, без неё цикл продолжал крутиться и держать
  /// ссылку на State.
  Future<LatLng?> _waitForFix() async {
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 4));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_myLocation != null) return _myLocation;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _myLocation;
  }

  void _zoomBy(double delta) {
    try {
      final double current = _controller.camera.zoom;
      final double next = (current + delta).clamp(4.0, 18.0);
      // Анимация вместо мгновенного `move` — без неё зум выглядит как
      // прыжок, теряется ощущение масштаба. 250 мс — компромисс между
      // плавностью и отзывчивостью.
      _controller.animatedMove(
        _controller.camera.center,
        next,
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {/* карта ещё не готова */}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Style>(
      future: _styleFuture,
      builder: (BuildContext context, AsyncSnapshot<Style> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            child: SizedBox(
              width: 24.r,
              height: 24.r,
              child: const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Не удалось загрузить карту',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.textSecondary),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Проверьте интернет или VPN',
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall(color: AppColors.textTertiary),
                ),
                SizedBox(height: 12.h),
                TextButton(
                  onPressed: () {
                    // Принудительно пересоздаём future, чтобы стиль
                    // подгрузился заново. Без setState FutureBuilder
                    // продолжает показывать старую ошибку.
                    setState(() {
                      _styleFuture = _loadLocalizedStyle();
                    });
                  },
                  child: Text(
                    'Повторить',
                    style: AppText.body(color: AppColors.primary)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }
        final Style style = snap.data!;

        // Жесты: если карта read-only — отключаем все. Если интерактивная —
        // включаем всё кроме `rotate`. Юзеры случайно крутили карту во
        // время pinch-zoom'а, маркеры оказывались под углом, пилюли
        // «север сверху» нет — выглядело как баг.
        final int interactionFlags = widget.interactive
            ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
            : InteractiveFlag.none;

        final Widget map = FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.initialCenter ??
                style.center ??
                const LatLng(55.7558, 37.6173),
            initialZoom: widget.initialZoom,
            maxZoom: 18,
            minZoom: 4,
            interactionOptions: InteractionOptions(flags: interactionFlags),
            onTap: widget.onMapTap == null
                ? null
                : (_, LatLng point) => widget.onMapTap!.call(point),
          ),
          children: <Widget>[
            VectorTileLayer(
              theme: _hideAdminBoundaries(style.theme),
              sprites: style.sprites,
              tileProviders: style.providers,
              // Дисковый кэш: 200 МБ с авто-LRU очисткой старых тайлов.
              // При повторном открытии экрана / приложения тайлы тянутся
              // из локального диска, без обращения в OpenFreeMap (Цюрих)
              // — это убирает «серые прогалины» при подгрузке.
              fileCacheMaximumSizeInBytes: _kTileCacheMaxSizeBytes,
              fileCacheTtl: _kTileCacheTtl,
              cacheFolder: _resolveTilesCacheFolder,
            ),
            if (widget.markers.isNotEmpty)
              MarkerLayer(
                // Ключ зависит от id всех маркеров. Без него `flutter_map`
                // переиспользует element и не обновляет отрисованный набор
                // Marker'ов при смене widget.markers — при применении
                // фильтров маркеры оставались прежними.
                key: ValueKey<String>(
                  widget.markers
                      .map((OpenFreeMapMarker m) => m.id)
                      .join(','),
                ),
                markers: widget.markers
                    .map((OpenFreeMapMarker m) {
                          final bool selected =
                              widget.selectedMarkerId == m.id;
                          // Базовый размер pin'а — 24×32 (по фигме). Для
                          // выбранного маркера слегка увеличиваем (× 1.4),
                          // чтобы было видно, какой именно выбран в списке.
                          final double iconW = selected ? 34.r : 24.r;
                          final double iconH = selected ? 46.r : 32.r;
                          return Marker(
                            point: m.point,
                            // Box чуть больше иконки — место под удобный тап.
                            width: iconW + 8.r,
                            height: iconH + 8.r,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  widget.onMarkerTap?.call(m.id),
                              child: Center(
                                child: Image.asset(
                                  'assets/images/icon_map_pin.webp',
                                  width: iconW,
                                  height: iconH,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        })
                    .toList(),
              ),
            // Синяя точка «моё местоположение» в стиле Google Maps —
            // рисуется ПОСЛЕ маркеров заказов, чтобы оставаться сверху.
            if (widget.showMyLocation && _myLocation != null)
              MarkerLayer(
                markers: <Marker>[
                  Marker(
                    point: _myLocation!,
                    width: 28.r,
                    height: 28.r,
                    alignment: Alignment.center,
                    child: const _MyLocationDot(),
                  ),
                ],
              ),
          ],
        );

        return Stack(
          children: <Widget>[
            map,
            if (widget.interactive &&
                (widget.showZoomControls || widget.showMyLocation))
              Positioned(
                right: 12.w,
                top: 0,
                bottom: widget.controlsBottomInset,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (widget.showZoomControls)
                        _MapZoomColumn(
                          onZoomIn: () => _zoomBy(1),
                          onZoomOut: () => _zoomBy(-1),
                        ),
                      if (widget.showZoomControls && widget.showMyLocation)
                        SizedBox(height: 12.h),
                      if (widget.showMyLocation)
                        _MapRoundButton(
                          asset: 'assets/images/icon_map_my_location.webp',
                          iconWidth: 24.w,
                          iconHeight: 24.h,
                          onTap: _onMyLocationTap,
                        ),
                    ],
                  ),
                ),
              ),
            Positioned(
              right: 4.w,
              bottom: 4.h,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3.r),
                ),
                child: Text(
                  '© OpenStreetMap © OpenMapTiles',
                  style: AppText.caption(color: AppColors.textTertiary)
                      .copyWith(fontSize: 9.sp),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Общая тень/обводка для кнопок управления картой.
///   - Drop shadow по фигме: x=0, y=4, blur=24, color #0C0C0D 16%
///   - Тонкая светло-серая обводка White 95 — даёт чёткий контур
///     белой кнопки на фоне белесых участков карты (облака, дороги).
BoxDecoration _mapBtnDecoration(BorderRadius radius) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: radius,
      border: Border.all(color: AppColors.divider, width: 1),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x290C0C0D),
          blurRadius: 24,
          offset: Offset(0, 4),
        ),
      ],
    );

/// Вертикальный блок «+ / −» зума. Ширина 40, высота 68 — по фигме.
/// Между кнопками тонкий разделитель в цвет обводки.
class _MapZoomColumn extends StatelessWidget {
  const _MapZoomColumn({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(10.r);
    return Container(
      width: 40.w,
      height: 68.h,
      decoration: _mapBtnDecoration(radius),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: <Widget>[
            Expanded(
              child: _MapTapCell(
                asset: 'assets/images/icon_map_zoom_in.webp',
                onTap: onZoomIn,
              ),
            ),
            Container(height: 1, color: AppColors.divider),
            Expanded(
              child: _MapTapCell(
                asset: 'assets/images/icon_map_zoom_out.webp',
                onTap: onZoomOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одиночная квадратная кнопка 40×40 (используется под «моё
/// местоположение»). Иконка центрируется внутри.
class _MapRoundButton extends StatelessWidget {
  const _MapRoundButton({
    required this.asset,
    required this.iconWidth,
    required this.iconHeight,
    required this.onTap,
  });

  final String asset;
  final double iconWidth;
  final double iconHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(10.r);
    return Container(
      width: 40.w,
      height: 40.h,
      decoration: _mapBtnDecoration(radius),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Image.asset(
              asset,
              width: iconWidth,
              height: iconHeight,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// Внутренняя ячейка-«пол-кнопка» с центрированной иконкой 24×24.
/// Используется внутри [_MapZoomColumn] для «+» и «−».
class _MapTapCell extends StatelessWidget {
  const _MapTapCell({required this.asset, required this.onTap});

  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Image.asset(
          asset,
          width: 24.w,
          height: 24.h,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Синяя точка «моё местоположение» в стиле Google Maps:
///   - внешний светло-синий ореол (полупрозрачный),
///   - белая обводка,
///   - внутренний насыщенно-синий круг с тенью.
/// Размер маркера фиксирован в Marker.width/height (28.r) — внутри
/// ореол занимает всю площадь, точка по центру 12.r.
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    const Color blue = Color(0xFF4285F4); // Google Maps location-blue
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: blue.withValues(alpha: 0.18),
          ),
        ),
        Container(
          width: 16.r,
          height: 16.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        Container(
          width: 12.r,
          height: 12.r,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: blue,
          ),
        ),
      ],
    );
  }
}
