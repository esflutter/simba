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

  // SMS Aero credentials исключены из клиента полностью: отправка SMS
  // идёт через PocketBase-эндпоинт `/api/auth/sms/send`, ключи только
  // на сервере. Раньше тут были `smsAeroEmail`/`smsAeroApiKey`/`Sender`
  // как `--dart-define` поля; если их кто-то передал бы при сборке
  // prod-APK, они становились бы `const String` и тривиально
  // извлекались из .apk через `strings`. Поля удалены, чтобы исключить
  // даже теоретическую возможность утечки.

  /// dev / staging / production
  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isDev => appEnv == 'dev';
  static bool get hasPocketbase => pocketbaseUrl.isNotEmpty;

  /// Контакты поддержки для шторки «Связаться с нами» в профиле.
  /// Передаются при сборке через `--dart-define=SUPPORT_*`. По умолчанию
  /// ПУСТЫЕ: если реальный контакт не передан (например, забыли в
  /// prod-сборке), соответствующая кнопка просто не показывается. Раньше
  /// здесь стояли placeholder-номера (+7 999 123-45-67 и выдуманный логин),
  /// и они уезжали в боевой APK — обращения уходили случайному человеку.
  /// Лучше скрыть канал, чем увести пользователя на фейковый номер.
  ///   --dart-define=SUPPORT_WHATSAPP_PHONE=+7XXX...
  ///   --dart-define=SUPPORT_TELEGRAM_USERNAME=...
  ///   --dart-define=SUPPORT_MAX_PHONE=+7XXX...
  static const String supportWhatsAppPhone =
      String.fromEnvironment('SUPPORT_WHATSAPP_PHONE');
  static const String supportTelegramUsername =
      String.fromEnvironment('SUPPORT_TELEGRAM_USERNAME');
  static const String supportMaxPhone =
      String.fromEnvironment('SUPPORT_MAX_PHONE');

  /// Настроен ли конкретный канал поддержки (контакт непустой). Кнопка
  /// показывается только при `true`.
  static bool get hasSupportWhatsApp => supportWhatsAppPhone.isNotEmpty;
  static bool get hasSupportTelegram => supportTelegramUsername.isNotEmpty;
  static bool get hasSupportMax => supportMaxPhone.isNotEmpty;
  static bool get hasAnySupportContact =>
      hasSupportWhatsApp || hasSupportTelegram || hasSupportMax;
}
