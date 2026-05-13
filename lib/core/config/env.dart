/// Конфигурация окружения. Значения читаются из `--dart-define` при сборке.
///
/// Пример запуска:
///   flutter run --dart-define=POCKETBASE_URL=... --dart-define=APP_ENV=dev
///
/// Для удобства локального запуска есть `run_dev.bat` в корне `app/`.
class Env {
  const Env._();

  /// URL PocketBase-инстанса. Все обращения к DaData идут ТОЛЬКО через
  /// PB-прокси (`/api/dadata/suggest-address`, `/api/dadata/geolocate-address`),
  /// токен DaData в клиенте больше не хранится.
  static const String pocketbaseUrl = String.fromEnvironment('POCKETBASE_URL');

  /// SMS Aero credentials. Сейчас temp в клиенте для dev (тестовый ключ
  /// бесплатный и не доставляет реальные SMS). В проде — переедет в
  /// PocketBase, в клиент НЕ попадёт.
  static const String smsAeroEmail = String.fromEnvironment('SMSAERO_EMAIL');
  static const String smsAeroApiKey = String.fromEnvironment('SMSAERO_API_KEY');
  static const String smsAeroSender =
      String.fromEnvironment('SMSAERO_SENDER', defaultValue: 'SMS Aero');

  /// dev / staging / production
  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isDev => appEnv == 'dev';
  static bool get hasPocketbase => pocketbaseUrl.isNotEmpty;
  static bool get hasSmsAero =>
      smsAeroEmail.isNotEmpty && smsAeroApiKey.isNotEmpty;
}
