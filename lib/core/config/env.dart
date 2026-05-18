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

  /// Контакты администратора для шторки «Связаться с нами» в профиле.
  /// Передаются через `--dart-define=SUPPORT_*`. До прихода реальных
  /// контактов держим placeholder-значения: кнопки всегда активны,
  /// открывают соответствующий мессенджер с подставленным номером /
  /// логином. Юзер увидит, что чат пустой — это нормально для preview.
  ///
  /// TODO(setup): подменить на реальные значения через `run_prod.bat`
  /// и CI-конфиг сборки, чтобы перекрыть defaultValue ниже:
  ///   --dart-define=SUPPORT_WHATSAPP_PHONE=+7XXX...
  ///   --dart-define=SUPPORT_TELEGRAM_USERNAME=...
  ///   --dart-define=SUPPORT_MAX_PHONE=+7XXX...
  static const String supportWhatsAppPhone = String.fromEnvironment(
    'SUPPORT_WHATSAPP_PHONE',
    defaultValue: '+79991234567',
  );
  static const String supportTelegramUsername = String.fromEnvironment(
    'SUPPORT_TELEGRAM_USERNAME',
    defaultValue: 'SimbAsupport',
  );
  static const String supportMaxPhone = String.fromEnvironment(
    'SUPPORT_MAX_PHONE',
    defaultValue: '+79991234567',
  );
}
