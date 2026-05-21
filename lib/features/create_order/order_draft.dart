import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/date_time_formatters.dart' show kPriceMax, kPriceMin;
import '../../data/local/preferences_store.dart';

@immutable
class OrderDraft {
  const OrderDraft({
    this.categoryId,
    this.title = '',
    this.description = '',
    this.address = '',
    this.location,
    this.priceRub = 0,
    this.scheduledAt,
    this.asap = true,
    this.photoPaths = const [],
    this.forOtherPhone,
    this.paymentMethod,
    this.addressFiasId,
    this.addressKladrId,
    this.cityFiasId,
    this.postalCode,
    this.qcGeo,
    this.clientUid,
  });

  final String? categoryId;
  final String title;
  final String description;
  final String address;
  final LatLng? location;
  final int priceRub;
  final DateTime? scheduledAt;
  final bool asap;
  final List<String> photoPaths;
  final String? forOtherPhone;
  final String? paymentMethod;

  // ── Структурные поля адреса (DaData) ────────────────────────────────
  // Адрес максимум до дома — квартира/подъезд/этаж/домофон в SimbA НЕ
  // хранятся: заказчик уточняет место встречи по звонку, а лишняя PII
  // только увеличивает поверхность утечки (152-ФЗ).
  /// FIAS-идентификатор выбранного адреса (на уровне fias_level подсказки).
  final String? addressFiasId;

  /// КЛАДР-идентификатор выбранного адреса.
  final String? addressKladrId;

  /// FIAS города (для последующих follow-up DaData-запросов).
  final String? cityFiasId;

  /// Почтовый индекс.
  final String? postalCode;

  /// Качество геокодинга DaData (0..5). 0 — точные координаты дома,
  /// 5 — координат нет. Бэкенд решает, дозволять ли заказ при низком qc_geo.
  final int? qcGeo;

  /// Клиентский UUID для идемпотентности create-запроса. Генерируется
  /// при первой попытке публикации и переживает уход с экрана: если
  /// юзер тапнул «Опубликовать», получил тайм-аут, ушёл назад и вернулся
  /// через минуту — повторная отправка с тем же UID не создаст дубликат
  /// (на сервере уникальный индекс по (customer, client_uid)). После
  /// успешной публикации `reset()` обнуляет вместе со всем черновиком.
  final String? clientUid;

  Map<String, dynamic> toJson() => {
        if (categoryId != null) 'categoryId': categoryId,
        'title': title,
        'description': description,
        'address': address,
        if (location != null) 'lat': location!.latitude,
        if (location != null) 'lng': location!.longitude,
        'priceRub': priceRub,
        if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
        'asap': asap,
        'photoPaths': photoPaths,
        if (forOtherPhone != null) 'forOtherPhone': forOtherPhone,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
        if (addressFiasId != null) 'addressFiasId': addressFiasId,
        if (addressKladrId != null) 'addressKladrId': addressKladrId,
        if (cityFiasId != null) 'cityFiasId': cityFiasId,
        if (postalCode != null) 'postalCode': postalCode,
        if (qcGeo != null) 'qcGeo': qcGeo,
        if (clientUid != null) 'clientUid': clientUid,
      };

  static OrderDraft fromJson(Map<String, dynamic> j) {
    final lat = j['lat'];
    final lng = j['lng'];
    final scheduled = j['scheduledAt'];
    // Файлы из image_picker лежат в кэше — после рестарта могут быть стёрты.
    // Раньше мы фильтровали список через `File(p).existsSync()` прямо в
    // `fromJson`, который вызывается синхронно из `Notifier.build()` на
    // холодном старте — это давало 1-3 sync-stat() на UI-isolate.
    // Теперь сохраняем все пути как есть; вид `Image.file(...)` сам
    // покажет errorBuilder для отсутствующих файлов, а реальный фильтр
    // делается лениво на этапе публикации (`order_summary_screen._publish`
    // → `File(p).existsSync()` уже на async-стадии).
    final photos = (j['photoPaths'] as List?)?.cast<String>() ?? const [];
    return OrderDraft(
      categoryId: j['categoryId'] as String?,
      title: (j['title'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      location: (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null,
      priceRub: (j['priceRub'] as num?)?.toInt() ?? 0,
      scheduledAt: scheduled is String ? DateTime.tryParse(scheduled) : null,
      asap: (j['asap'] as bool?) ?? true,
      photoPaths: photos,
      forOtherPhone: j['forOtherPhone'] as String?,
      paymentMethod: j['paymentMethod'] as String?,
      addressFiasId: j['addressFiasId'] as String?,
      addressKladrId: j['addressKladrId'] as String?,
      cityFiasId: j['cityFiasId'] as String?,
      postalCode: j['postalCode'] as String?,
      qcGeo: (j['qcGeo'] as num?)?.toInt(),
      clientUid: j['clientUid'] as String?,
    );
  }

  bool get isEmpty =>
      categoryId == null &&
      title.isEmpty &&
      description.isEmpty &&
      address.isEmpty &&
      location == null &&
      priceRub == 0 &&
      scheduledAt == null &&
      asap == true &&
      photoPaths.isEmpty &&
      forOtherPhone == null &&
      paymentMethod == null &&
      addressFiasId == null &&
      addressKladrId == null &&
      cityFiasId == null &&
      postalCode == null &&
      qcGeo == null;

  bool get isReady =>
      categoryId != null &&
      title.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      location != null &&
      priceRub >= kPriceMin &&
      priceRub <= kPriceMax;

  OrderDraft copyWith({
    String? categoryId,
    String? title,
    String? description,
    String? address,
    LatLng? location,
    int? priceRub,
    DateTime? scheduledAt,
    bool? asap,
    List<String>? photoPaths,
    String? forOtherPhone,
    String? paymentMethod,
    String? addressFiasId,
    String? addressKladrId,
    String? cityFiasId,
    String? postalCode,
    int? qcGeo,
    String? clientUid,
    bool clearScheduled = false,
    bool clearForOther = false,
    bool clearAddressMeta = false,
    bool clearLocation = false,
  }) =>
      OrderDraft(
        categoryId: categoryId ?? this.categoryId,
        title: title ?? this.title,
        description: description ?? this.description,
        address: address ?? this.address,
        location: clearLocation ? null : location ?? this.location,
        priceRub: priceRub ?? this.priceRub,
        scheduledAt: clearScheduled ? null : scheduledAt ?? this.scheduledAt,
        asap: asap ?? this.asap,
        photoPaths: photoPaths ?? this.photoPaths,
        forOtherPhone: clearForOther ? null : forOtherPhone ?? this.forOtherPhone,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        addressFiasId:
            clearAddressMeta ? null : addressFiasId ?? this.addressFiasId,
        addressKladrId:
            clearAddressMeta ? null : addressKladrId ?? this.addressKladrId,
        cityFiasId: clearAddressMeta ? null : cityFiasId ?? this.cityFiasId,
        postalCode: clearAddressMeta ? null : postalCode ?? this.postalCode,
        qcGeo: clearAddressMeta ? null : qcGeo ?? this.qcGeo,
        clientUid: clientUid ?? this.clientUid,
      );
}

class OrderDraftController extends Notifier<OrderDraft> {
  PreferencesStore? get _prefs {
    try {
      return ref.read(preferencesProvider);
    } catch (_) {
      return null; // тесты могут не подменять prefs — это допустимо
    }
  }

  /// Debounce-таймер записи в SharedPreferences. Раньше каждое `update()`
  /// (= каждый keystroke в форме создания заказа) делало `prefs.setString`.
  /// При вводе названия 50 символов это 50 sync-flush на диск.
  /// Теперь записываем не чаще, чем раз в [_persistDebounce] после
  /// последнего изменения.
  Timer? _persistTimer;
  static const Duration _persistDebounce = Duration(milliseconds: 300);

  @override
  OrderDraft build() {
    // Когда provider утилизируется (например, при logout через invalidate),
    // дожимаем pending-запись синхронно — иначе несохранённый черновик
    // потеряется при следующем cold-start. На моках провайдер «вечный».
    ref.onDispose(() {
      if (_persistTimer?.isActive == true) {
        _persistTimer?.cancel();
        _persistNow(state);
      }
    });

    final raw = _prefs?.draftJson;
    if (raw == null || raw.isEmpty) return const OrderDraft();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return OrderDraft.fromJson(map);
    } catch (_) {
      return const OrderDraft();
    }
  }

  /// Запланировать persist с дебаунсом. Любой новый `update` сбрасывает
  /// предыдущий таймер; запись произойдёт, когда юзер «успокоится».
  void _persist(OrderDraft d) {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () => _persistNow(d));
  }

  /// Немедленная запись в prefs. Используется как fallback при dispose и
  /// при reset() — там debounce неуместен (сразу очищаем, чтобы при
  /// перезапуске черновик не «воскрес»).
  Future<void> _persistNow(OrderDraft d) async {
    final p = _prefs;
    if (p == null) return;
    try {
      if (d.isEmpty) {
        await p.clearDraft();
      } else {
        await p.saveDraftJson(jsonEncode(d.toJson()));
      }
    } catch (e) {
      // prefs не записался: на следующий cold-start черновик потеряется.
      // Это терпимо, но в логах должно быть видно — иначе тихая регрессия
      // (особенно при тестах с заполненным emulator-storage).
      if (kDebugMode) {
        debugPrint('[OrderDraft] persist failed: $e');
      }
    }
  }

  void update({
    String? categoryId,
    String? title,
    String? description,
    String? address,
    LatLng? location,
    int? priceRub,
    DateTime? scheduledAt,
    bool? asap,
    List<String>? photoPaths,
    String? forOtherPhone,
    String? paymentMethod,
    String? addressFiasId,
    String? addressKladrId,
    String? cityFiasId,
    String? postalCode,
    int? qcGeo,
    String? clientUid,
    bool clearScheduled = false,
    bool clearForOther = false,
    bool clearAddressMeta = false,
    bool clearLocation = false,
  }) {
    state = state.copyWith(
      categoryId: categoryId,
      title: title,
      description: description,
      address: address,
      location: location,
      priceRub: priceRub,
      scheduledAt: scheduledAt,
      asap: asap,
      photoPaths: photoPaths,
      forOtherPhone: forOtherPhone,
      paymentMethod: paymentMethod,
      addressFiasId: addressFiasId,
      addressKladrId: addressKladrId,
      cityFiasId: cityFiasId,
      postalCode: postalCode,
      qcGeo: qcGeo,
      clientUid: clientUid,
      clearScheduled: clearScheduled,
      clearForOther: clearForOther,
      clearAddressMeta: clearAddressMeta,
      clearLocation: clearLocation,
    );
    _persist(state);
  }

  void reset() {
    _persistTimer?.cancel();
    state = const OrderDraft();
    // reset = немедленная очистка, без debounce. Иначе если приложение
    // закроется через <300мс после reset (например, юзер свайпнул из
    // тасков), pending-debounce не сработает, и при перезапуске
    // выскочит «воскресший» черновик.
    _persistNow(state);
  }

  /// Сброс адресных полей draft'а при смене города. Категория, название,
  /// описание, цена, дата — остаются. Раньше адрес/координаты/FIAS висели
  /// от старого города, и заказчик упирался в гард «адрес не в вашем городе»
  /// только на summary после заполнения формы заново.
  void clearAddress() {
    state = state.copyWith(
      address: '',
      location: null,
      clearLocation: true,
      clearAddressMeta: true,
    );
    _persist(state);
  }
}

final orderDraftProvider =
    NotifierProvider<OrderDraftController, OrderDraft>(OrderDraftController.new);
