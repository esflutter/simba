import 'package:latlong2/latlong.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/models.dart';

/// Преобразование PocketBase-записи `orders` в доменную модель [Order].
/// Цены в БД хранятся в копейках (price_kopecks), на клиенте — в рублях.
///
/// Если передать [pb] — поле `photoPaths` будет содержать полные URL,
/// собранные через `pb.files.getUrl(...)`. Иначе вернётся пустой список
/// (имена файлов без базового URL для UI бесполезны).
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
    forOtherPhone: r.getStringValue('for_other_phone').isEmpty
        ? null
        : r.getStringValue('for_other_phone'),
  );
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
