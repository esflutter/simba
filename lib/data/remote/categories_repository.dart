import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_data.dart';
import '../models/models.dart';
import 'pocketbase_client.dart';

/// Список категорий из PocketBase (с fallback на моки).
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final pb = ref.read(pocketbaseProvider);
  if (pb == null) return MockData.categories;
  try {
    final records = await pb
        .collection('categories')
        .getFullList(
          filter: 'is_active = true',
          sort: 'sort_order',
        )
        // См. комментарий в cities_repository — без таймаута UI висит
        // на спиннере при первом запуске и плохой сети.
        .timeout(const Duration(seconds: 15));
    return records
        .map((r) => Category(
              id: r.id,
              name: r.getStringValue('name'),
              icon: r.getStringValue('icon'),
            ))
        .toList();
  } catch (e) {
    // Fallback на встроенный список — лучше показать стандартные категории,
    // чем пустой экран. В логах увидим причину для отладки.
    if (kDebugMode) {
      debugPrint('[categories_repository] live fetch failed, using mock: $e');
    }
    return MockData.categories;
  }
});
