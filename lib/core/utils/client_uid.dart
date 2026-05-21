import 'dart:math';

/// Генерирует UUID v4 для клиентского ключа идемпотентности.
///
/// Используется в `OrdersRepository.create`: клиент создаёт UID при
/// первой попытке отправки заказа и передаёт его на сервер. Если сеть
/// оборвётся ровно между «тело улетело» и «ответ получен», повторная
/// отправка с тем же UID не создаст дубликат — сервер вернёт ту же
/// запись через уникальный индекс `(customer, client_uid)`.
///
/// Без зависимости от пакета `uuid` — алгоритм RFC 4122 §4.4 на
/// `Random.secure` помещается в десяток строк.
String generateClientUid() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  // Версия 4 (random) — старшие 4 бита 7-го октета = 0100.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Вариант RFC 4122 — старшие 2 бита 9-го октета = 10.
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final s = bytes.map(hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
      '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20, 32)}';
}
