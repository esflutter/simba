import 'package:geolocator/geolocator.dart';

/// Запрашивает разрешение на геолокацию, если оно ещё не выдано.
///
/// Возвращает `true`, если после вызова приложение имеет доступ к
/// местоположению («whileInUse» или «always»). В противном случае
/// возвращает `false` — вызывающая сторона сама решает, как реагировать
/// (показать ли карту без точки, открыть ли настройки, и т.п.).
Future<bool> ensureLocationPermission() async {
  // Все вызовы geolocator могут бросить PlatformException — например,
  // на устройствах без Google Play Services, при кривой инициализации
  // плагина, или если системный сервис локации временно не отвечает.
  // Без try/catch исключение поднималось вверх и обваливало весь
  // экран карты / флоу выбора адреса. Молча возвращаем false —
  // вызывающая сторона уже умеет рендерить «карта без точки».
  try {
    // Системный сервис геолокации выключен — запрашивать разрешение
    // бесполезно: пользователь всё равно не сможет дать доступ, пока
    // не включит GPS в настройках устройства.
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  } catch (_) {
    return false;
  }
}
