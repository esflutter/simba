import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_client.dart';

/// Подсказка адреса от DaData. Хранит как человекочитаемые строки, так и
/// структурные идентификаторы (FIAS/КЛАДР), которые мы пробрасываем на бэкенд
/// для последующего использования (нормализация, антифрод, аналитика).
class AddressSuggestion {
  const AddressSuggestion({
    required this.value,
    required this.unrestrictedValue,
    this.point,
    this.fiasId,
    this.kladrId,
    this.cityFiasId,
    this.cityName,
    this.street,
    this.house,
    this.postalCode,
    this.qcGeo,
    this.fiasLevel,
  });

  /// «ул. Тверская, 12»
  final String value;

  /// «г Москва, ул Тверская, д 12»
  final String unrestrictedValue;

  /// Координаты дома/строения, если DaData распознал точку.
  final LatLng? point;

  /// FIAS-идентификатор адреса (на уровне fias_level).
  final String? fiasId;

  /// КЛАДР-идентификатор адреса.
  final String? kladrId;

  /// FIAS города (для locations в follow-up запросах).
  final String? cityFiasId;

  /// Название города.
  final String? cityName;

  /// Улица (без префикса «ул.»).
  final String? street;

  /// Номер дома.
  final String? house;

  /// Почтовый индекс.
  final String? postalCode;

  /// Качество геокодинга DaData (0..5): 0 — точные координаты дома,
  /// 5 — координат нет совсем. См. doc DaData.
  final int? qcGeo;

  /// Уровень детализации: house / street / city. Используется чтобы отсеять
  /// слишком общие подсказки при выборе адреса для заказа.
  final String? fiasLevel;

  /// Подсказка указывает на конкретный дом/строение.
  bool get hasHouse => fiasLevel == '8' || fiasLevel == '9' || fiasLevel == '10';

  /// Парсер ответа DaData (как от прямого API, так и от PB-прокси, который
  /// просто проксирует ответ без изменений).
  static AddressSuggestion? tryFromDadata(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final data = (m['data'] is Map)
        ? (m['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final value = m['value']?.toString() ?? '';
    if (value.isEmpty) return null;
    final geoLat = double.tryParse(data['geo_lat']?.toString() ?? '');
    final geoLon = double.tryParse(data['geo_lon']?.toString() ?? '');
    final qcGeoStr = data['qc_geo']?.toString();
    return AddressSuggestion(
      value: value,
      unrestrictedValue: m['unrestricted_value']?.toString() ?? value,
      point: (geoLat != null && geoLon != null) ? LatLng(geoLat, geoLon) : null,
      fiasId: data['fias_id']?.toString(),
      kladrId: data['kladr_id']?.toString(),
      cityFiasId: data['city_fias_id']?.toString(),
      cityName: data['city']?.toString(),
      street: data['street']?.toString(),
      house: data['house']?.toString(),
      postalCode: data['postal_code']?.toString(),
      qcGeo: qcGeoStr != null ? int.tryParse(qcGeoStr) : null,
      fiasLevel: data['fias_level']?.toString(),
    );
  }
}

/// Результат запроса подсказок. Отличает «пусто» от «ошибка сети»:
/// UI может показать «Не удалось загрузить подсказки» вместо «нет
/// подходящих адресов». Старый метод [DaDataClient.suggest] оставлен
/// для совместимости (возвращает только список).
class SuggestResult {
  const SuggestResult({required this.suggestions, this.error});
  final List<AddressSuggestion> suggestions;

  /// `null` — успех (даже если список пуст); иначе машинно-читаемый код:
  /// `network`, `timeout`, `http_<code>`, `parse`.
  final String? error;

  bool get isError => error != null;
}

/// Клиент DaData. Ходит ИСКЛЮЧИТЕЛЬНО через PocketBase-прокси —
/// `/api/dadata/suggest-address` и `/api/dadata/geolocate-address`. Это
/// гарантирует, что секретный токен DaData никогда не попадает в APK.
class DaDataClient {
  DaDataClient(this._pb, {http.Client? httpClient}) : _injectedHttp = httpClient;

  final PocketBase? _pb;

  /// Инжектируемый клиент — только для тестов. В обычной работе `null`, и
  /// запросы идут через [sendWithSharedClient], который сам пересоздаёт
  /// закрытый общий клиент (типичный сценарий после долгого сна устройства).
  /// Раньше здесь хранилась ЗАХВАЧЕННАЯ ссылка на `sharedHttpClient`: после
  /// его сброса в любом другом запросе подсказки/геокодинг молча падали с
  /// «client already closed» до конца сессии (ошибка маскировалась под «нет
  /// сети»). Теперь актуальный клиент берётся на каждый вызов.
  final http.Client? _injectedHttp;

  bool get _isLive => _pb != null;

  /// Единая точка похода на PB-прокси: через инжектированный клиент (тесты)
  /// либо через общий клиент с авто-восстановлением.
  Future<http.Response> _post(PocketBase pb, String path, Object body) async {
    Future<http.Response> op(http.Client c) => c
        .post(
          Uri.parse('${pb.baseURL}$path'),
          headers: _headers(pb),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));
    final injected = _injectedHttp;
    Future<http.Response> send() =>
        injected != null ? op(injected) : sendWithSharedClient(op);
    var resp = await send();
    // Сессия истекла ровно во время ввода адреса (часто после возврата из
    // фона): прокси отвечает 401/403. Обновляем токен один раз и повторяем —
    // иначе подсказки и геокодинг молча отваливались до ручного перелогина,
    // как и в остальных репозиториях. op() строит заголовки заново, поэтому
    // повтор уходит уже с новым токеном.
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      try {
        await pb.refreshAuthSingleFlight();
        resp = await send();
      } catch (_) {/* refresh не удался — отдаём исходный ответ как есть */}
    }
    return resp;
  }

  /// Подсказки по адресу.
  ///
  /// [regionFiasId] / [cityFiasId] / [cityName] — задают ограничение поиска
  /// в порядке приоритета (FIAS точнее, чем строковое имя). Если ни один не
  /// указан — поиск без ограничения по локации.
  ///
  /// Если нужно отличать «нет совпадений» от «нет связи» — используй
  /// [suggestWithStatus]; этот метод — тонкая обёртка над ним.
  Future<List<AddressSuggestion>> suggest(
    String query, {
    int count = 7,
    String? regionFiasId,
    String? cityFiasId,
    String? cityName,
    bool restrictToCity = true,
  }) async {
    final res = await suggestWithStatus(
      query,
      count: count,
      regionFiasId: regionFiasId,
      cityFiasId: cityFiasId,
      cityName: cityName,
      restrictToCity: restrictToCity,
    );
    return res.suggestions;
  }

  /// То же, что [suggest], но возвращает [SuggestResult] с признаком
  /// сетевой ошибки. Используется на экранах, где важно отличать
  /// «нет совпадений» от «нет связи».
  Future<SuggestResult> suggestWithStatus(
    String query, {
    int count = 7,
    String? regionFiasId,
    String? cityFiasId,
    String? cityName,
    bool restrictToCity = true,
  }) async {
    if (!_isLive) {
      return const SuggestResult(suggestions: []);
    }
    final pb = _pb!;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SuggestResult(suggestions: []);
    }
    final body = <String, dynamic>{
      'query': trimmed,
      'count': count,
      'from_bound': {'value': 'city'},
      'to_bound': {'value': 'house'},
    };
    final locations = <Map<String, dynamic>>[];
    if (regionFiasId != null && regionFiasId.isNotEmpty) {
      locations.add({'region_fias_id': regionFiasId});
    } else if (cityFiasId != null && cityFiasId.isNotEmpty) {
      locations.add({'city_fias_id': cityFiasId});
    } else if (cityName != null && cityName.isNotEmpty) {
      locations.add({'city': cityName});
    }
    if (locations.isNotEmpty) {
      body['locations'] = locations;
      if (restrictToCity) body['restrict_value'] = true;
    }
    return _suggestInternal(pb, body);
  }

  Future<SuggestResult> _suggestInternal(
    PocketBase pb,
    Map<String, dynamic> body,
  ) async {
    final http.Response resp;
    try {
      resp = await _post(pb, '/api/dadata/suggest-address', body);
    } on TimeoutException {
      return const SuggestResult(suggestions: [], error: 'timeout');
    } catch (_) {
      return const SuggestResult(suggestions: [], error: 'network');
    }
    if (resp.statusCode != 200) {
      return SuggestResult(
        suggestions: const [],
        error: 'http_${resp.statusCode}',
      );
    }
    try {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = (data is Map && data['suggestions'] is List)
          ? data['suggestions'] as List
          : const [];
      final items = list
          .map<AddressSuggestion?>((it) => AddressSuggestion.tryFromDadata(it))
          .whereType<AddressSuggestion>()
          .toList(growable: false);
      return SuggestResult(suggestions: items);
    } catch (_) {
      return const SuggestResult(suggestions: [], error: 'parse');
    }
  }

  /// Обратное геокодирование: по координатам — ближайший адрес.
  Future<AddressSuggestion?> geolocate(
    LatLng point, {
    int radiusMeters = 500,
    int count = 5,
  }) async {
    if (!_isLive) return null;
    final pb = _pb!;
    try {
      final resp = await _post(pb, '/api/dadata/geolocate-address', {
        'lat': point.latitude,
        'lon': point.longitude,
        'radius_meters': radiusMeters,
        'count': count,
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = (data is Map && data['suggestions'] is List)
          ? data['suggestions'] as List
          : const [];
      if (list.isEmpty) return null;
      return AddressSuggestion.tryFromDadata(list.first);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers(PocketBase pb) {
    final token = pb.authStore.token;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  void dispose() {
    // Нечего закрывать: общий клиент живёт в pocketbase_client и
    // переиспользуется всем приложением; инжектированный (в тестах)
    // закрывает тот, кто его создал.
  }
}

/// Провайдер DaData-клиента. Привязан к PocketBase: если PB не настроен
/// (моки/тесты) — клиент работает в no-op режиме и возвращает пустые
/// результаты.
///
/// Запросы идут через общий `sendWithSharedClient` из pocketbase_client —
/// он переиспользует keep-alive соединение и сам пересоздаёт клиент, если
/// тот закрылся (после долгого сна устройства).
final dadataClientProvider = Provider<DaDataClient>((ref) {
  final pb = ref.read(pocketbaseProvider);
  final client = DaDataClient(pb);
  ref.onDispose(client.dispose);
  return client;
});
