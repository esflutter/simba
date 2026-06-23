import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../mock/mock_data.dart';
import '../models/models.dart';
import 'pocketbase_client.dart';

/// Источник списка городов. Если бэкенд доступен — берём из PocketBase,
/// иначе работает старая мок-логика (`MockData.cities`).
final citiesProvider = FutureProvider<List<City>>((ref) async {
  final pb = ref.read(pocketbaseProvider);
  if (pb == null) {
    return MockData.cities;
  }
  try {
    final records = await pb
        .collection('cities')
        .getFullList(
          filter: 'is_active = true',
          sort: 'sort_order',
        )
        // Без таймаута зависший сокет держит спиннер по 60+ секунд (это
        // один из первых экранов после логина). При проблеме — мягкий
        // fallback на встроенный список ниже.
        .timeout(const Duration(seconds: 15));
    return records.map((r) {
      // bounds_radius_km может быть null если миграция 1700000009 ещё не
      // отработала — используем дефолт из City.boundsRadiusKm (50).
      final radius = r.getDoubleValue('bounds_radius_km');
      final fias = r.getStringValue('dadata_fias_id');
      return City(
        id: r.id,
        name: r.getStringValue('name'),
        center: LatLng(
          r.getDoubleValue('lat'),
          r.getDoubleValue('lng'),
        ),
        dadataFiasId: fias.isEmpty ? null : fias,
        boundsRadiusKm: radius > 0 ? radius : 50.0,
      );
    }).toList();
  } catch (e) {
    // На случай если бэкенд недоступен — мягкий fallback на моки,
    // чтобы UI не сломался.
    if (kDebugMode) {
      debugPrint('[cities_repository] live fetch failed, using mock: $e');
    }
    return MockData.cities;
  }
});

/// Карта «id города → отображаемое имя». Нужна, чтобы подставлять город к
/// адресу заказа везде, КРОМЕ каталога (на вкладке «Заказы» все заказы одного
/// выбранного города — дублировать город в каждой карточке незачем).
/// Пока список городов грузится — отдаём имена из встроенного справочника.
final cityNamesProvider = Provider<Map<String, String>>((ref) {
  final list = ref.watch(citiesProvider).maybeWhen(
        data: (xs) => xs,
        orElse: () => MockData.cities,
      );
  return {for (final c in list) c.id: c.name};
});
