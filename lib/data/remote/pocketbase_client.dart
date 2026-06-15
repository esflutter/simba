import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../mock/app_state.dart';
import 'auth_repository.dart' show purgeLocalUserData;

/// Глобальный клиент PocketBase. URL берётся из --dart-define POCKETBASE_URL.
/// Если URL пустой — клиент не создаётся и репозитории падают на моки.
///
/// Дефолтные URL для разработки:
///   Android-эмулятор:  http://10.0.2.2:8090
///   iOS-симулятор:     http://127.0.0.1:8090
///   Физ. устройство:   http://<ваш-локальный-IP>:8090  (в той же Wi-Fi)
///
/// Провайдер переопределяется в `main()` через `overrideWithValue`, чтобы
/// прокинуть готовый PocketBase с AsyncAuthStore (persist токена через
/// SharedPreferences). Без override провайдер кидает UnimplementedError.
final pocketbaseProvider = Provider<PocketBase?>(
  (ref) => throw UnimplementedError('pocketbaseProvider must be overridden in main()'),
);

/// Ключ, под которым раньше хранился JSON {token, model} в обычных
/// SharedPreferences. Сейчас используется только для разовой миграции —
/// при первом запуске после обновления токен переезжает отсюда в
/// защищённое хранилище.
const String kPbAuthPrefsKey = 'pb_auth';

/// Ключ для защищённого хранилища (Android Keystore / iOS Keychain).
const String kPbAuthSecureKey = 'simba.pb_auth';

/// Опции защищённого хранилища.
///
/// На Android по умолчанию `flutter_secure_storage` пишет в обычный
/// SharedPreferences под маской — без EncryptedSharedPreferences токен
/// читается тривиально на рутованном устройстве. Принудительно
/// включаем шифрование на стороне OS.
///
/// На iOS дефолтный `first_unlock` уровень доступа подходит — токен
/// читается после первой разблокировки устройства пользователем, что
/// нужно для авторестарта фонового потока.
const _kSecureAndroidOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);
const _kSecureIOSOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock,
);

const FlutterSecureStorage simbaSecureStorage = FlutterSecureStorage(
  aOptions: _kSecureAndroidOptions,
  iOptions: _kSecureIOSOptions,
);

/// Общий `http.Client` для прямых HTTP-вызовов из приложения
/// (DaData, кастомные ручки бэка) — переиспользует TCP/TLS между запросами.
///
/// ВАЖНО: getter, а не `final` глобал. После hot restart Dart VM
/// перезапускает Dart-код, но нативные сокеты предыдущего `http.Client`
/// могут остаться полузакрытыми — следующий запрос валится с
/// `ClientException: Client is already closed`. Создаём новый клиент
/// при первом обращении после рестарта.
///
/// ВАЖНО: НЕ передавать этот клиент в PocketBase SDK через
/// `httpClientFactory` — SDK 0.22 закрывает клиент после запроса,
/// если фабрика задана. Для SDK используется отдельная фабрика, которая
/// создаёт свежий `http.Client` на каждый вызов (см. [buildPocketBase]).
http.Client? _sharedHttpClientOrNull;
http.Client get sharedHttpClient {
  final c = _sharedHttpClientOrNull;
  if (c != null) return c;
  return _sharedHttpClientOrNull = http.Client();
}

/// Сбросить кэшированный клиент. Вызывается при ClientException
/// «already closed» — новый запрос получит свежий клиент.
void resetSharedHttpClient() {
  try {
    _sharedHttpClientOrNull?.close();
  } catch (_) {}
  _sharedHttpClientOrNull = null;
}

/// Хелпер для HTTP-запросов через [sharedHttpClient] с авто-сбросом
/// при `ClientException: Client is already closed`.
///
/// Сценарий, который покрывает: на iOS/Android при long sleep устройства
/// нативный сокет в нашем `http.Client` помечается как closed, но Dart-side
/// клиент об этом не знает. Первый запрос после wake-up валится с
/// `ClientException`. Один раз сбрасываем кэш и повторяем.
///
/// Использовать вместо прямых `sharedHttpClient.post(...)` / `get(...)`.
Future<http.Response> sendWithSharedClient(
  Future<http.Response> Function(http.Client client) op,
) async {
  try {
    return await op(sharedHttpClient);
  } on http.ClientException catch (e) {
    // Точный матч на текст SDK, без обращения к приватному coded полю.
    final msg = e.message.toLowerCase();
    if (!msg.contains('already closed') && !msg.contains('client is closed')) {
      rethrow;
    }
    resetSharedHttpClient();
    return op(sharedHttpClient);
  }
}

/// Фабрика клиента: создаётся один раз в `main()`. Возвращает null,
/// если URL не задан (моки).
///
/// Async — потому что чтение токена идёт из защищённого хранилища
/// (Android Keystore / iOS Keychain). Если в новом хранилище ничего
/// нет, но есть legacy-токен в SharedPreferences (юзер обновил
/// приложение со старой версии), переносим его и сразу удаляем из
/// prefs — иначе он там лежал бы в открытом виде.
Future<PocketBase?> buildPocketBase(
  SharedPreferences prefs, {
  FlutterSecureStorage secureStorage = simbaSecureStorage,
}) async {
  if (!Env.hasPocketbase) return null;

  String? initial;
  try {
    initial = await secureStorage.read(key: kPbAuthSecureKey);
  } catch (_) {
    // На свежем устройстве/симуляторе первое чтение может бросить
    // PlatformException (нет ключа) — у разных версий плагина по-
    // разному, на всякий случай ловим всё.
    initial = null;
  }
  if (initial == null) {
    final legacy = prefs.getString(kPbAuthPrefsKey);
    if (legacy != null && legacy.isNotEmpty) {
      bool migrated = false;
      try {
        await secureStorage.write(key: kPbAuthSecureKey, value: legacy);
        initial = legacy;
        migrated = true;
      } catch (_) {
        // Если защищённое хранилище недоступно (старая ОС/эмулятор
        // без поддержки Keystore) — оставляем токен в prefs, чтобы
        // юзера не разлогинивать. Без этого fallback'а старые
        // устройства теряли бы сессию при первом запуске после
        // обновления.
        initial = legacy;
      }
      // Чистим legacy-ключ ТОЛЬКО при успешной миграции. Если запись
      // в secure storage упала, prefs.remove до сих пор всё равно
      // отрабатывал — и юзер с проблемным Keystore терял сессию при
      // каждом запуске (память сессии исчезала вместе с процессом).
      if (migrated) {
        await prefs.remove(kPbAuthPrefsKey);
      }
    }
  }

  final store = AsyncAuthStore(
    save: (String raw) async =>
        secureStorage.write(key: kPbAuthSecureKey, value: raw),
    initial: initial,
    clear: () async => secureStorage.delete(key: kPbAuthSecureKey),
  );
  return PocketBase(
    Env.pocketbaseUrl,
    authStore: store,
    // SDK 0.22 при заданной фабрике сам владеет клиентом и закрывает его
    // после каждого запроса. Поэтому возвращаем НОВЫЙ http.Client на каждый
    // вызов — иначе после первого запроса все следующие падают с
    // `ClientException: Client is already closed`.
    //
    // Без фабрики (если не передать httpClientFactory) SDK создаёт один
    // статический клиент в конструкторе — после hot reload его нативные
    // сокеты замораживаются, и getOne/getList висят до таймаута. Фабрика
    // решает обе проблемы: каждый запрос получает свежий, живой клиент.
    httpClientFactory: () => http.Client(),
  );
}

/// Проверка доступности бэкенда — используем для feature-toggle между
/// репозиторием PB и мок-репозиторием.
bool usePocketbase(WidgetRef ref) {
  return ref.read(pocketbaseProvider) != null;
}

/// Собирает URL файла-вложения, когда нет полноценного RecordModel под рукой
/// (например, ответ от кастомной ручки `/api/orders/feed` отдаёт только
/// массив имён файлов и id записи). Раньше для этого синтезировали fake
/// `RecordModel({...})` и звали `pb.files.getUrl()` — рабочий, но грязный
/// хак. Здесь собираем canonical-путь PB напрямую: `/api/files/:cid/:rid/:fn`.
String pbFileUrl(
  PocketBase pb, {
  required String collection,
  required String recordId,
  required String filename,
}) {
  final base = pb.baseURL.replaceAll(RegExp(r'/+$'), '');
  final c = Uri.encodeComponent(collection);
  final r = Uri.encodeComponent(recordId);
  final f = Uri.encodeComponent(filename);
  return '$base/api/files/$c/$r/$f';
}

/// Single-flight для `authRefresh`: пока один вызов в полёте, остальные
/// ждут его результат, а не шлют второй refresh параллельно.
///
/// Без этого при возврате приложения из фона одновременно инвалидируются
/// несколько провайдеров (лента, мои заказы, мои отклики), каждый ловит
/// 401 на своём первом запросе и шлёт собственный authRefresh с одним и
/// тем же старым токеном. SMS Aero / PB отвечают каждому новым токеном,
/// и поздно вернувшийся ответ затирает свежий — следующий запрос снова
/// получает 401, цикл. Симптом: иногда после фона приложение выкидывает
/// на /auth/phone при валидной сессии.
///
/// Expando хранит Future per PocketBase instance, чтобы не пересекаться
/// между тестами или возможными несколькими клиентами.
final Expando<Future<void>> _authRefreshInFlight = Expando('pb_refresh');

Future<void> _refreshTokenSingleFlight(PocketBase pb) {
  final pending = _authRefreshInFlight[pb];
  if (pending != null) return pending;
  final fut = pb
      .collection('users')
      .authRefresh()
      .timeout(const Duration(seconds: 15));
  _authRefreshInFlight[pb] = fut;
  // Очищаем слот после завершения (успешного или нет), чтобы следующий
  // 401 запустил свежий refresh, а не получал stale Future.
  // .ignore(): whenComplete возвращает ОТДЕЛЬНЫЙ Future, который при
  // падении refresh завершается той же ошибкой; без слушателя это
  // «unhandled async error» (шум в крэш-репортинге, валит строгие тесты).
  // Сам refresh ждут вызыватели через возвращаемый fut.
  fut.whenComplete(() {
    if (identical(_authRefreshInFlight[pb], fut)) {
      _authRefreshInFlight[pb] = null;
    }
  }).ignore();
  return fut;
}

/// Универсальная обёртка для PB-вызовов: ловит 401/403 (истёкший токен),
/// один раз пробует `authRefresh()` и повторяет операцию. Если refresh
/// тоже упал — чистит authStore и пробрасывает исключение, чтобы
/// вызывающий мог корректно показать ошибку.
///
/// Используется как `pb.withAuthRetry(() => pb.collection(...).getOne(...))`.
/// Если нужно ещё и сбросить AppController.user (чтобы redirect-guard в
/// роутере перенаправил на /auth/phone) — используй [withPbAuthRetry] ниже,
/// которая принимает Ref.
extension PocketBaseAuthRetry on PocketBase {
  Future<T> withAuthRetry<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on ClientException catch (e) {
      final code = e.statusCode;
      if (code != 401 && code != 403) rethrow;
      try {
        await _refreshTokenSingleFlight(this);
      } catch (e) {
        // Стираем сессию ТОЛЬКО при реальной ошибке авторизации refresh'а
        // (просроченный refresh-токен → 401/403). Транспортный сбой
        // (таймаут/обрыв сети) валидную сессию не трогает — иначе после
        // фона при моргнувшей сети юзера выкидывало на вход.
        if (e is ClientException && (e.statusCode == 401 || e.statusCode == 403)) {
          authStore.clear();
        }
        rethrow;
      }
      return op();
    }
  }

  /// Запустить (или дождаться) общий single-flight refresh токена.
  /// Используется в местах, где идёт прямой `http.post` к нашим кастомным
  /// ручкам (мы их не оборачиваем в `withAuthRetry`, потому что это
  /// чистый http, а не PB API). Все вызывающие делят одну Future —
  /// никаких параллельных refresh на разных провайдерах.
  Future<void> refreshAuthSingleFlight() {
    return _refreshTokenSingleFlight(this);
  }
}

/// Обёртка над `pb.withAuthRetry`, которая дополнительно дёргает
/// `appController.logout()`, если refresh не получилось. Без logout'а
/// `AppController.user` остался бы валидным и redirect-guard в роутере
/// не отправил бы юзера на /auth/phone — он бы зависал на текущем экране
/// с пустыми данными после rethrow.
///
/// Используется во всех PB-репозиториях, чтобы один и тот же refresh-fail
/// сценарий вёл к одному и тому же UI-эффекту.
Future<T> withPbAuthRetry<T>(Ref ref, Future<T> Function() op) async {
  final pb = ref.read(pocketbaseProvider);
  if (pb == null) {
    // Нет live PB — мок-ветка должна была сработать выше. Если попали сюда,
    // у вызывающего ошибка ветвления `_isLive`. Бросаем StateError, чтобы
    // не молчать в debug.
    throw StateError(
        'withPbAuthRetry called without live PocketBase — check _isLive guard');
  }
  try {
    return await pb.withAuthRetry(op);
  } catch (e) {
    if (!pb.authStore.isValid) {
      try {
        ref.read(appControllerProvider.notifier).logout();
        // Полная локальная очистка кэша картинок и провайдеров — иначе
        // данные прошлого юзера остаются после принудительного выхода.
        purgeLocalUserData(ref);
      } catch (_) {
        // appControllerProvider может быть не зарегистрирован в тестовом
        // ProviderContainer — это допустимо, главное чтобы исходный
        // exception ушёл выше.
      }
    }
    rethrow;
  }
}
