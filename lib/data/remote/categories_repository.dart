import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_data.dart';
import '../models/models.dart';
import 'pocketbase_client.dart';

/// Список категорий из PocketBase (с fallback на моки).
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final pb = ref.read(pocketbaseProvider);
  if (pb == null) return MockData.categories;
  try {
    final records = await pb.collection('categories').getFullList(
          filter: 'is_active = true',
          sort: 'sort_order',
        );
    return records
        .map((r) => Category(
              id: r.id,
              name: r.getStringValue('name'),
              icon: r.getStringValue('icon'),
            ))
        .toList();
  } catch (_) {
    return MockData.categories;
  }
});
