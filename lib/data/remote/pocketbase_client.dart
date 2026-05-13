import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';

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

/// Фабрика клиента: создаётся один раз в `main()` после `SharedPreferences.getInstance()`.
/// Возвращает null, если URL не задан (моки).
PocketBase? buildPocketBase(SharedPreferences prefs) {
  if (!Env.hasPocketbase) return null;
  final store = AsyncAuthStore(
    save: (String raw) async => prefs.setString(kPbAuthPrefsKey, raw),
    initial: prefs.getString(kPbAuthPrefsKey),
    clear: () async => prefs.remove(kPbAuthPrefsKey),
  );
  return PocketBase(Env.pocketbaseUrl, authStore: store);
}

/// Проверка доступности бэкенда — используем для feature-toggle между
/// репозиторием PB и мок-репозиторием.
bool usePocketbase(WidgetRef ref) {
  return ref.read(pocketbaseProvider) != null;
}
