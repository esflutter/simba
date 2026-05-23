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
    // Single-flight: если параллельный вызов уже регистрирует — ждём его.
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _doRegister(userId);
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _doRegister(String userId) async {
    final messaging = FirebaseMessaging.instance;

    debugPrint('[FCM] register start for user=$userId');

    // Permission. На iOS обязательно — без alert/badge/sound ничего не
    // покажется. На Android 13+ системный диалог POST_NOTIFICATIONS,
    // на старших Android — no-op (доступ выдан по умолчанию).
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] permission status=${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] permission request failed: $e');
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
      debugPrint('[FCM] getToken returned len=${token?.length ?? 0}');
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) {
      debugPrint('[FCM] token empty — skip save');
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
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_saveTokenToServer);
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

    if (pb != null && userId != null) {
      try {
        // 5 секунд: logout не должен залипать на минуту при тормозящей
        // сети. Даже если запрос не дойдёт — следующий логин перезапишет.
        await pb
            .send(_kFcmTokenEndpoint, method: 'POST', body: {'token': ''})
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('FCM token clear failed: $e');
      }
    }

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
      debugPrint('[FCM] save skipped: pb=null (mock mode)');
      return false;
    }
    final userId = pb.authStore.record?.id;
    if (userId == null) {
      debugPrint('[FCM] save skipped: authStore.record=null');
      return false;
    }
    try {
      await pb
          .send(_kFcmTokenEndpoint, method: 'POST', body: {'token': token})
          .timeout(const Duration(seconds: 10));
      debugPrint('[FCM] token saved for user $userId');
      return true;
    } catch (e) {
      debugPrint('[FCM] token save failed: $e');
      return false;
    }
  }
}

final fcmRepositoryProvider = Provider<FcmRepository>((ref) {
  return FcmRepository(ref);
});
