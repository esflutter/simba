import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pocketbase_client.dart';

/// Регистрация FCM-токена устройства на сервере и обработка входящих
/// пушей. Сценарии:
///   * `registerForCurrentUser()` — вызывается ПОСЛЕ авторизации, когда
///     в PocketBase authStore лежит valid user. Запрашивает permission,
///     получает FCM-токен, сохраняет в `users.fcm_token`, подписывается
///     на token refresh.
///   * `clearForCurrentUser()` — вызывается ПЕРЕД логаутом. Чистит
///     `users.fcm_token` на сервере (чтобы новый владелец того же
///     устройства не получал чужие пуши) и инвалидирует токен локально.
///
/// Foreground-сообщения сейчас не показываем как системное уведомление —
/// PocketBase realtime инвалидирует данные, экран обновляется. Если в
/// будущем понадобится баннер при открытом приложении, добавим
/// flutter_local_notifications.
/// fcm_token в users помечен hidden — обычный PATCH через PB API
/// тихо игнорируется, нужен кастомный endpoint.
const _kFcmTokenEndpoint = '/api/me/fcm-token';

class FcmRepository {
  FcmRepository(this._ref);
  final Ref _ref;

  /// Логи FCM-цепочки. Гейтим за режимом отладки: эти сообщения содержат
  /// id пользователя и тексты ошибок, в release они оседали бы в системном
  /// логе телефона (видны через ADB/logcat). На время отладки пушей их
  /// специально оставляли «голыми» (видны в release-сборке); сейчас, когда
  /// цепочка работает, прячем.
  void _fcmLog(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  StreamSubscription<String>? _tokenRefreshSub;
  // Защита от шторма регистраций при cold-start: splash, feed и my_orders
  // независимо дёргают tryRefreshAuth, и каждый _consumeAuthEnvelope зовёт
  // registerForCurrentUser. Без дедупа 3 запроса в Firebase + 3 PATCH'а на
  // сервер за секунду. Запоминаем какой userId последний раз регистрировали
  // и время — повторный вызов в течение 5 минут просто пропускаем.
  String? _lastRegisteredUserId;
  DateTime _lastRegisteredAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kRegisterDedupWindow = Duration(minutes: 5);
  // Single-flight: пока идёт регистрация одного юзера, параллельные
  // вызовы получают тот же Future вместо запуска новой цепочки запросов
  // в Firebase. Без этого три cold-start вызова _consumeAuthEnvelope
  // (splash, feed, my_orders) реально дёргают три параллельных
  // getToken + три PATCH на /users/:id.
  Future<void>? _inFlight;
  // Чей именно in-flight сейчас выполняется. Нужен, чтобы при быстрой
  // смене аккаунта (logout → login другим юзером, пока регистрация
  // первого ещё в полёте — getToken тянется до ~25 сек на медленной
  // сети) НЕ отдавать второму юзеру чужую регистрацию. Без привязки к
  // userId токен второго юзера не попадал на сервер, и он не получал ни
  // одного пуша до перезапуска приложения.
  String? _inFlightUserId;
  // Последний успешно отправленный на сервер токен ЭТОГО устройства. При
  // выходе из аккаунта сообщаем его серверу, чтобы он погасил строку именно
  // этого устройства (несколько устройств на аккаунт — остальные продолжают
  // получать пуши). Если null (приложение перезапускали) — старый протокол
  // token="" просто чистит legacy-зеркало.
  String? _lastSentToken;

  // Платформа устройства для строки push_tokens (поле обязательное).
  String get _platformTag {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'android';
    }
  }

  /// Зарегистрировать токен текущего залогиненного пользователя на
  /// сервере. Идемпотентно: повторный вызов с тем же токеном просто
  /// перезапишет то же значение, ошибки не вызовет.
  Future<void> registerForCurrentUser() async {
    final pb = _ref.read(pocketbaseProvider);
    if (pb == null) return;
    final userId = pb.authStore.record?.id;
    if (userId == null) return;

    // Дедуп: тот же юзер успешно регистрировался недавно — пропускаем.
    if (userId == _lastRegisteredUserId &&
        DateTime.now().difference(_lastRegisteredAt) < _kRegisterDedupWindow) {
      return;
    }
    // Single-flight: ждём параллельную регистрацию ТОЛЬКО если она про
    // того же пользователя. Если в полёте регистрация другого аккаунта
    // (быстрая смена юзера на общем устройстве) — запускаем свою, иначе
    // токен текущего юзера потеряется.
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightUserId == userId) return inFlight;
    final future = _doRegister(userId);
    _inFlight = future;
    _inFlightUserId = userId;
    try {
      await future;
    } finally {
      // Снимаем слот только если его не перехватила более поздняя
      // регистрация (другой юзер). Без проверки identical поздний
      // login обнулял бы чужой in-flight.
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightUserId = null;
      }
    }
  }

  Future<void> _doRegister(String userId) async {
    final messaging = FirebaseMessaging.instance;

    _fcmLog('[FCM] register start for user=$userId');

    // Permission. На iOS обязательно — без alert/badge/sound ничего не
    // покажется. На Android 13+ системный диалог POST_NOTIFICATIONS,
    // на старших Android — no-op (доступ выдан по умолчанию).
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).timeout(const Duration(seconds: 10));
      _fcmLog('[FCM] permission status=${settings.authorizationStatus}');
    } catch (e) {
      _fcmLog('[FCM] permission request failed: $e');
      // Permission не критичен для регистрации токена — токен можно
      // получить и без него, просто пуши не будут показываться.
    }

    String? token;
    try {
      // getToken может зависнуть на устройствах без Google Play Services
      // (huawei новые без GMS, или приложение установлено до полной
      // инициализации FCM). Таймаут 15 сек — достаточно для нормальной
      // сети, не вешает auth-флоу на минуты.
      token = await messaging
          .getToken()
          .timeout(const Duration(seconds: 15));
      _fcmLog('[FCM] getToken returned len=${token?.length ?? 0}');
    } catch (e) {
      _fcmLog('[FCM] getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) {
      _fcmLog('[FCM] token empty — skip save');
      return;
    }

    final saved = await _saveTokenToServer(token);
    if (saved) {
      _lastRegisteredUserId = userId;
      _lastRegisteredAt = DateTime.now();
    }

    // FCM обновляет токен при переустановке/очистке данных/восстановлении
    // из бэкапа. Без подписки сервер останется со старым токеном.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_onTokenRefresh);
  }

  /// Реакция на смену FCM-токена устройства (ротация). Регистрируем НОВЫЙ
  /// токен и сразу гасим строку СТАРОГО — иначе у одного устройства осталось
  /// бы две живые записи, и в окне ротации пуш мог прийти дважды (старый токен
  /// ещё валиден). Гашение старого сервер не лимитирует (это не регистрация).
  Future<void> _onTokenRefresh(String newToken) async {
    final old = _lastSentToken;
    await _saveTokenToServer(newToken);
    if (old != null && old.isNotEmpty && old != newToken) {
      final pb = _ref.read(pocketbaseProvider);
      if (pb != null) {
        try {
          await pb
              .send(_kFcmTokenEndpoint,
                  method: 'POST', body: {'token': old, 'remove': true})
              .timeout(const Duration(seconds: 5));
        } catch (_) {/* не критично — старый токен умрёт и подчистится сам */}
      }
    }
  }

  /// Очистить токен текущего пользователя. Вызывается до самого logout —
  /// иначе мы потеряем доступ к userId.
  Future<void> clearForCurrentUser() async {
    final pb = _ref.read(pocketbaseProvider);
    final userId = pb?.authStore.record?.id;

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    // Сбрасываем dedup-маркер — следующий логин (другим юзером или тем
    // же после logout) должен зарегистрировать токен заново.
    _lastRegisteredUserId = null;
    _lastRegisteredAt = DateTime.fromMillisecondsSinceEpoch(0);
    // Сбрасываем in-flight слот: зависшая регистрация прошлого юзера не
    // должна заблокировать регистрацию следующего. Сам Future отменить
    // нельзя, но он завершится безвредно (юзер уже вышел), а новый логин
    // запустит свежую регистрацию.
    _inFlight = null;
    _inFlightUserId = null;

    if (pb != null && userId != null) {
      try {
        // 5 секунд: logout не должен залипать на минуту при тормозящей
        // сети. Даже если запрос не дойдёт — следующий логин перезапишет.
        // Multi-device: сообщаем серверу КОНКРЕТНЫЙ токен этого устройства,
        // чтобы он погасил только ЕГО строку, не трогая другие устройства
        // аккаунта. Если токен сессии не сохранён в памяти (после перезапуска
        // приложения) — берём текущий токен устройства напрямую, чтобы выход
        // оставался точечным. Пустой токен (старый протокол, чистит лишь
        // legacy-зеркало) — только если и это не удалось.
        String? deviceToken = _lastSentToken;
        if (deviceToken == null) {
          try {
            deviceToken = await FirebaseMessaging.instance
                .getToken()
                .timeout(const Duration(seconds: 5));
          } catch (_) {/* токен недоступен — отправим пустой */}
        }
        final Map<String, dynamic> clearBody =
            (deviceToken != null && deviceToken.isNotEmpty)
                ? {'token': deviceToken, 'remove': true}
                : {'token': ''};
        await pb
            .send(_kFcmTokenEndpoint, method: 'POST', body: clearBody)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('FCM token clear failed: $e');
      }
    }
    _lastSentToken = null;

    // Локально удаляем FCM-токен — следующий getToken() выдаст новый.
    // Без этого старый владелец устройства и новый получили бы пуши
    // друг друга, если FCM выдал бы тот же токен (теоретически).
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) debugPrint('FCM deleteToken failed: $e');
    }
  }

  /// Возвращает true при подтверждённом сохранении на сервере. Вызывающая
  /// сторона использует это, чтобы не ставить dedup-маркер при неудаче —
  /// иначе следующая попытка будет заблокирована на 5 минут зря.
  Future<bool> _saveTokenToServer(String token) async {
    final pb = _ref.read(pocketbaseProvider);
    if (pb == null) {
      _fcmLog('[FCM] save skipped: pb=null (mock mode)');
      return false;
    }
    final userId = pb.authStore.record?.id;
    if (userId == null) {
      _fcmLog('[FCM] save skipped: authStore.record=null');
      return false;
    }
    try {
      await pb
          .send(_kFcmTokenEndpoint, method: 'POST', body: {
        'token': token,
        'platform': _platformTag,
      }).timeout(const Duration(seconds: 10));
      _lastSentToken = token;
      _fcmLog('[FCM] token saved for user $userId');
      return true;
    } catch (e) {
      _fcmLog('[FCM] token save failed: $e');
      return false;
    }
  }
}

final fcmRepositoryProvider = Provider<FcmRepository>((ref) {
  return FcmRepository(ref);
});
