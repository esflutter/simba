import 'package:flutter/foundation.dart';

import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';

/// Возвращает читаемое имя категории заказа.
///
/// Приоритет:
///   1. `order.categoryName` — приходит с бэка через `expand=category.name`,
///      покрывает любые категории, в т.ч. добавленные без обновления клиента.
///   2. `MockData.categories` по `categoryId` — fallback на справочник в коде.
///   3. Последняя категория («Другое») — если ничего не подошло; пишем
///      в debugPrint, чтобы факт рассинхронизации с бэком не уходил молча.
///
/// До рефакторинга идентичная функция была скопирована в 4+ экранов
/// (`feed_screen`, `my_orders_screen`, `search_screen`, `history_screen`,
/// `create_order_screen`). Любое изменение логики (например, новый fallback)
/// требовало синхронной правки во всех файлах — типовая копипаста.
String categoryNameOf(Order o) {
  if (o.categoryName != null && o.categoryName!.isNotEmpty) {
    return o.categoryName!;
  }
  for (final c in MockData.categories) {
    if (c.id == o.categoryId) return c.name;
  }
  if (kDebugMode) {
    debugPrint(
        '[categoryNameOf] order ${o.id}: categoryId "${o.categoryId}" '
        'not in MockData.categories — fallback to "${MockData.categories.last.name}"');
  }
  return MockData.categories.last.name;
}
