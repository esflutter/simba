import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/models.dart';

/// Преобразование PocketBase-записи `orders` в доменную модель [Order].
/// Цены в БД хранятся в копейках (price_kopecks), на клиенте — в рублях.
///
/// Если передать [pb] — поле `photoPaths` будет содержать полные URL,
/// собранные через `pb.files.getUrl(...)`. Иначе вернётся пустой список
/// (имена файлов без базового URL для UI бесполезны).
///
/// Если в записи присутствует `expand` для customer/executor/category —
/// имена и URL фото из expand'ов материализуются в соответствующие поля
/// [Order]: это позволяет UI отрисовать карточку без дополнительных
/// запросов в `users`/`categories`.
Order orderFromRecord(RecordModel r, [PocketBase? pb]) {
  final rawStatus = r.getStringValue('status');
  final workDoneAt = _parseDate(r.getStringValue('work_done_by_executor_at'));
  final paymentReceivedAt =
      _parseDate(r.getStringValue('payment_received_at'));
  OrderStatus status = _statusFromString(rawStatus);
  if (status == OrderStatus.accepted &&
      workDoneAt != null &&
      paymentReceivedAt == null) {
    status = OrderStatus.awaitingPayment;
  }

  final customer = _firstExpand(r, 'customer');
  final executor = _firstExpand(r, 'executor');
  final category = _firstExpand(r, 'category');

  return Order(
    id: r.id,
    customerId: r.getStringValue('customer'),
    categoryId: r.getStringValue('category'),
    title: r.getStringValue('title'),
    description: r.getStringValue('description'),
    address: r.getStringValue('address'),
    location: LatLng(r.getDoubleValue('lat'), r.getDoubleValue('lng')),
    priceRub: (r.getDoubleValue('price_kopecks') / 100).round(),
    status: status,
    createdAt: DateTime.tryParse(r.getStringValue('created')) ?? DateTime.now(),
    scheduledAt: _parseDate(r.getStringValue('scheduled_at')),
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
    paymentMethod: _paymentMethodFromString(r.getStringValue('payment_method')),
    forOtherPhone: r.getStringValue('for_other_phone').isEmpty
        ? null
        : r.getStringValue('for_other_phone'),
    customerName: _nonEmpty(customer?.getStringValue('name')),
    customerPhotoUrl: _firstFileUrl(customer, 'photo', pb),
    executorName: _nonEmpty(executor?.getStringValue('name')),
    executorPhotoUrl: _firstFileUrl(executor, 'photo', pb),
    categoryName: _nonEmpty(category?.getStringValue('name')),
    completedAt: _parseDate(r.getStringValue('completed_at')),
    workDoneAt: workDoneAt,
    workConfirmedAt:
        _parseDate(r.getStringValue('work_confirmed_by_customer_at')),
    paymentReceivedAt: paymentReceivedAt,
    cityId: _nonEmpty(r.getStringValue('city')),
  );
}

/// Маппинг строки `payment_method` из БД в [PaymentMethod].
///
/// Сейчас в SimbA только `cash` (наличные). Если в будущем добавится
/// `cashless`/`card` — расширь enum в `models.dart` и добавь сюда case.
PaymentMethod _paymentMethodFromString(String s) {
  switch (s) {
    case 'cash':
    default:
      return PaymentMethod.cash;
  }
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

OrderStatus _statusFromString(String s) {
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
      return OrderStatus.open;
  }
}

DateTime? _parseDate(String s) {
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Собирает полные URL фото-вложений через `pb.files.getUrl`. Без [pb]
/// вернёт пустой список — голые имена файлов в UI всё равно бесполезны.
List<String> _filePhotoUrls(RecordModel r, String field, PocketBase? pb) {
  final raw = r.get<dynamic>(field);
  if (raw is! List) return const [];
  final names = raw.cast<String>();
  if (pb == null) return const [];
  return names
      .map((name) => pb.files.getUrl(r, name).toString())
      .toList(growable: false);
}
