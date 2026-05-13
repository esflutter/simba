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
    final records = await pb.collection('cities').getFullList(
          filter: 'is_active = true',
          sort: 'sort_order',
        );
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
  } catch (_) {
    // На случай если бэкенд недоступен — мягкий fallback на моки,
    // чтобы UI не сломался.
    return MockData.cities;
  }
});
