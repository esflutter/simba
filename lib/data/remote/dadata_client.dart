import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';

/// Подсказка адреса от DaData. Содержит человекочитаемую строку и координаты,
/// если DaData их распознал. У некоторых результатов координат нет (район
/// без конкретного дома) — тогда [point] = null.
class AddressSuggestion {
  const AddressSuggestion({
    required this.value,
    required this.unrestrictedValue,
    this.point,
    this.fiasLevel,
  });

  /// «ул. Тверская, 12»
  final String value;

  /// «г Москва, ул Тверская, д 12»
  final String unrestrictedValue;

  /// Координаты дома/строения, если DaData распознал точку.
  final LatLng? point;

  /// Уровень детализации: house / street / city. Используется чтобы отсеять
  /// слишком общие подсказки при выборе адреса для заказа.
  final String? fiasLevel;

  bool get hasHouse => fiasLevel == '8' || fiasLevel == '9' || fiasLevel == '10';
}

/// Клиент DaData Suggest API. Для MVP вызывает DaData напрямую с
/// публичным токеном; на бэкенде стороне (PocketBase) — заменим на
/// прокси-эндпоинт `/api/dadata/suggest-address` с серверным токеном.
class DaDataClient {
  DaDataClient({http.Client? client}) : _client = client ?? http.Client();

  static const _suggestUrl =
      'https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/address';
  static const _geolocateUrl =
      'https://suggestions.dadata.ru/suggestions/api/4_1/rs/geolocate/address';

  final http.Client _client;

  /// Подсказки по адресу. [cityName] ограничивает выборку конкретным городом
  /// (по названию региона/города — DaData распознаёт).
  Future<List<AddressSuggestion>> suggest(
    String query, {
    String? cityName,
    int count = 7,
  }) async {
    if (!Env.hasDadata) return const [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final body = <String, dynamic>{'query': trimmed, 'count': count};
    if (cityName != null && cityName.isNotEmpty) {
      // DaData принимает region/city/settlement в locations.
      // Для городов-миллионников достаточно `region` = название.
      body['locations'] = [
        {'city': cityName},
      ];
      body['restrict_value'] = true;
    }

    try {
      final resp = await _client
          .post(
            Uri.parse(_suggestUrl),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = json['suggestions'] as List?;
      if (list == null) return const [];
      return list
          .map((e) => _parseSuggestion(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Обратное геокодирование: по координатам — ближайший адрес. Возвращает
  /// первый результат или null, если ничего не нашлось.
  Future<AddressSuggestion?> geolocate(LatLng point) async {
    if (!Env.hasDadata) return null;
    try {
      final resp = await _client
          .post(
            Uri.parse(_geolocateUrl),
            headers: _headers,
            body: jsonEncode({
              'lat': point.latitude,
              'lon': point.longitude,
              'count': 1,
              'radius_meters': 200,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = json['suggestions'] as List?;
      if (list == null || list.isEmpty) return null;
      return _parseSuggestion(list.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Token ${Env.dadataApiKey}',
      };

  AddressSuggestion _parseSuggestion(Map<String, dynamic> raw) {
    final data = (raw['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lat = double.tryParse((data['geo_lat'] ?? '').toString());
    final lng = double.tryParse((data['geo_lon'] ?? '').toString());
    return AddressSuggestion(
      value: (raw['value'] as String?) ?? '',
      unrestrictedValue: (raw['unrestricted_value'] as String?) ?? '',
      point: (lat != null && lng != null) ? LatLng(lat, lng) : null,
      fiasLevel: data['fias_level']?.toString(),
    );
  }

  void dispose() => _client.close();
}
