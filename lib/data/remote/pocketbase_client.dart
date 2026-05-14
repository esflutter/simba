import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../mock/app_state.dart';

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

/// Ключ, под которым AsyncAuthStore сохраняет JSON {token, model} в prefs.
const String kPbAuthPrefsKey = 'pb_auth';

/// Один общий `http.Client` на всё приложение — переиспользует TCP-соединение
/// и TLS-сессию между запросами. SDK 0.22 не имеет параметра `reuseHTTPClient`,
/// но принимает кастомный `httpClientFactory`: возвращаем одну и ту же
/// инстанцию — эффект тот же.
final http.Client _sharedHttpClient = http.Client();

/// Тот же общий клиент, экспортированный для других репозиториев (DaData,
/// auth, users) — чтобы избежать создания собственного `http.Client` на
/// каждый репозиторий и тоже переиспользовать keep-alive соединение.
http.Client get sharedHttpClient => _sharedHttpClient;

/// Фабрика клиента: создаётся один раз в `main()` после `SharedPreferences.getInstance()`.
/// Возвращает null, если URL не задан (моки).
PocketBase? buildPocketBase(SharedPreferences prefs) {
  if (!Env.hasPocketbase) return null;
  final store = AsyncAuthStore(
    save: (String raw) async => prefs.setString(kPbAuthPrefsKey, raw),
    initial: prefs.getString(kPbAuthPrefsKey),
    clear: () async => prefs.remove(kPbAuthPrefsKey),
  );
  return PocketBase(
    Env.pocketbaseUrl,
    authStore: store,
    httpClientFactory: () => _sharedHttpClient,
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
        await collection('users')
            .authRefresh()
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        authStore.clear();
        rethrow;
      }
      return op();
    }
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
      } catch (_) {
        // appControllerProvider может быть не зарегистрирован в тестовом
        // ProviderContainer — это допустимо, главное чтобы исходный
        // exception ушёл выше.
      }
    }
    rethrow;
  }
}
