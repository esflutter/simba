import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/utils/pb_date.dart';
import '../models/models.dart';

/// Преобразование PocketBase-записи `orders` в доменную модель [Order].
/// Цены хранятся и в БД, и в модели одинаково — в рублях (price_rub, int).
/// Эквайринга в приложении нет, копейки бессмысленны.
///
/// Если передать [pb] — поле `photoPaths` будет содержать полные URL,
/// собранные через `pb.files.getUrl(...)`. Иначе вернётся пустой список
/// (имена файлов без базового URL для UI бесполезны).
///
/// Если в записи присутствует `expand` для customer/executor/category —
/// имена и URL фото из expand'ов материализуются в соответствующие поля
/// [Order]: это позволяет UI отрисовать карточку без дополнительных
/// запросов в `users`/`categories`.
///
/// Возвращает `null`, если в записи отсутствует обязательное поле
/// `customer` (битый ответ от бэка). Вызывающий должен отфильтровать
/// результат: `records.map(orderFromRecord).whereType<Order>()`.
Order? orderFromRecord(RecordModel r, [PocketBase? pb]) {
  final customerId = r.getStringValue('customer');
  if (customerId.isEmpty) {
    // Битая запись: без customer теряется логика «свой/чужой заказ»
    // (всё сравнение с auth.id даст false). Лучше пропустить и
    // залогировать, чем тащить мусор в UI.
    if (kDebugMode) {
      debugPrint('orderFromRecord: skipping order ${r.id} — empty customer');
    }
    return null;
  }
  final rawStatus = r.getStringValue('status');
  final workDoneAt = parsePbDate(r.getStringValue('work_done_by_executor_at'));
  final paymentReceivedAt =
      parsePbDate(r.getStringValue('payment_received_at'));
  final parsed = _statusFromString(rawStatus);
  if (parsed == null) {
    // Бэк ввёл новый статус, которого клиент ещё не знает (refunded,
    // expired_auto и т.п.). Раньше fallback на OrderStatus.open подкидывал
    // такие заказы в ленту, юзер тапал «Откликнуться» и сразу получал
    // 400 от сервера. Лучше тихо пропустить запись — её увидят клиенты
    // обновлённой версии.
    if (kDebugMode) {
      debugPrint(
          'orderFromRecord: skipping order ${r.id} — unknown status "$rawStatus"');
    }
    return null;
  }
  OrderStatus status = parsed;
  if (status == OrderStatus.accepted &&
      workDoneAt != null &&
      paymentReceivedAt == null) {
    status = OrderStatus.awaitingPayment;
  }

  // Битая `created` (теоретически невозможна — PB всегда автозаполняет
  // поле, но защищаемся от рассинхронизации схемы). Используем эпоху как
  // sentinel: для ленты сортировка «новые сверху» отправит такие записи
  // в самый конец, для «Мои заказы» юзер всё равно увидит свой заказ
  // (раньше мы пропускали → заказ исчезал из истории, что хуже фейковой
  // даты). debugPrint поможет найти источник проблемы.
  var createdAt = parsePbDate(r.getStringValue('created'));
  if (createdAt == null) {
    if (kDebugMode) {
      debugPrint('orderFromRecord: order ${r.id} has invalid `created` — using epoch fallback');
    }
    createdAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  final customer = _firstExpand(r, 'customer');
  final executor = _firstExpand(r, 'executor');
  final category = _firstExpand(r, 'category');

  return Order(
    id: r.id,
    customerId: customerId,
    categoryId: r.getStringValue('category'),
    title: r.getStringValue('title'),
    description: r.getStringValue('description'),
    address: r.getStringValue('address'),
    location: LatLng(r.getDoubleValue('lat'), r.getDoubleValue('lng')),
    priceRub: r.getIntValue('price_rub'),
    status: status,
    createdAt: createdAt,
    scheduledAt: parsePbDate(r.getStringValue('scheduled_at')),
    asap: r.getBoolValue('asap'),
    executorId: r.getStringValue('executor').isEmpty
        ? null
        : r.getStringValue('executor'),
    photoPaths: _filePhotoUrls(r, 'photos', pb),
    // Список откликов (responses) намеренно НЕ загружается в маппере:
    // (1) это отдельная коллекция `order_responses`, expand'ить её
    //     многие-к-одному на каждый order — это N+1;
    // (2) UI грузит pending-отклики через `pendingExecutorIdsProvider`
    //     (см. `features/orders/responses_screen.dart`), чему достаточно
    //     одного запроса с filter по нужному orderId.
    // Поэтому здесь оставляем пустой список.
    responses: const [],
    paymentMethod:
        PaymentMethodMapping.fromDbValue(r.getStringValue('payment_method')),
    forOtherPhone: r.getStringValue('for_other_phone').isEmpty
        ? null
        : r.getStringValue('for_other_phone'),
    customerName: _nonEmpty(customer?.getStringValue('name')),
    customerPhotoUrl: _firstFileUrl(customer, 'photo', pb),
    executorName: _nonEmpty(executor?.getStringValue('name')),
    executorPhotoUrl: _firstFileUrl(executor, 'photo', pb),
    categoryName: _nonEmpty(category?.getStringValue('name')),
    completedAt: parsePbDate(r.getStringValue('completed_at')),
    workDoneAt: workDoneAt,
    workConfirmedAt:
        parsePbDate(r.getStringValue('work_confirmed_by_customer_at')),
    paymentReceivedAt: paymentReceivedAt,
    cityId: _nonEmpty(r.getStringValue('city')),
    relistedAt: parsePbDate(r.getStringValue('relisted_at')),
  );
}

/// Достаёт первый expand для отношения. PB SDK 0.22 нормализует expand в
/// `Map<String, List<RecordModel>>` (даже для single-relation), поэтому
/// достаточно взять первый элемент списка.
RecordModel? _firstExpand(RecordModel r, String relation) {
  try {
    final single = r.get<RecordModel?>('expand.$relation');
    if (single != null) return single;
    final list = r.get<List<RecordModel>?>('expand.$relation');
    if (list != null && list.isNotEmpty) return list.first;
    return null;
  } catch (_) {
    return null;
  }
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

/// URL первого файла из multi-file поля (или одиночного file) на записи.
/// `users.photo` обычно одиночный, `categories.icon` — тоже. Безопасно
/// обрабатывает оба случая.
String? _firstFileUrl(RecordModel? rec, String field, PocketBase? pb) {
  if (rec == null || pb == null) return null;
  try {
    final raw = rec.get<dynamic>(field);
    String? name;
    if (raw is String && raw.isNotEmpty) {
      name = raw;
    } else if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is String && first.isNotEmpty) name = first;
    }
    if (name == null) return null;
    return pb.files.getUrl(rec, name).toString();
  } catch (_) {
    return null;
  }
}

/// Возвращает `null` для статусов, которых клиент не знает. Раньше
/// возвращали fallback на `OrderStatus.open`, что подкидывало записи
/// в новом статусе в активную ленту — юзер пытался откликнуться и
/// сразу получал отказ от сервера. Логика "пропустить запись" живёт
/// в [orderFromRecord], а здесь — чистая трансляция.
OrderStatus? _statusFromString(String s) {
  switch (s) {
    case 'open':
      return OrderStatus.open;
    case 'accepted':
      return OrderStatus.accepted;
    case 'completed':
      return OrderStatus.completed;
    case 'cancelled':
      return OrderStatus.cancelled;
    default:
      return null;
  }
}

/// Собирает полные URL фото-вложений через `pb.files.getUrl`. Без [pb]
/// вернёт пустой список — голые имена файлов в UI всё равно бесполезны.
List<String> _filePhotoUrls(RecordModel r, String field, PocketBase? pb) {
  final raw = r.get<dynamic>(field);
  if (raw is! List) return const [];
  // whereType<String>() — устойчиво к битым записям, где в массиве
  // photos оказалось null или число. `cast<String>()` падает лениво
  // при первой итерации, что роняло весь экран ленты.
  final names = raw.whereType<String>();
  if (pb == null) return const [];
  return names
      .map((name) => pb.files.getUrl(r, name).toString())
      .toList(growable: false);
}
