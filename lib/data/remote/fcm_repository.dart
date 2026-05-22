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
class FcmRepository {
  FcmRepository(this._ref);
  final Ref _ref;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Зарегистрировать токен текущего залогиненного пользователя на
  /// сервере. Идемпотентно: повторный вызов с тем же токеном просто
  /// перезапишет то же значение, ошибки не вызовет.
  Future<void> registerForCurrentUser() async {
    final pb = _ref.read(pocketbaseProvider);
    if (pb == null) return;
    final userId = pb.authStore.record?.id;
    if (userId == null) return;

    final messaging = FirebaseMessaging.instance;

    // Permission. На iOS обязательно — без alert/badge/sound ничего не
    // покажется. На Android 13+ системный диалог POST_NOTIFICATIONS,
    // на старших Android — no-op (доступ выдан по умолчанию).
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('FCM permission request failed: $e');
      // Permission не критичен для регистрации токена — токен можно
      // получить и без него, просто пуши не будут показываться.
    }

    String? token;
    try {
      token = await messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('FCM getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) return;

    await _saveTokenToServer(token);

    // Подписка на refresh. FCM может обновить токен при переустановке
    // приложения, очистке данных, удалении/восстановлении из бэкапа.
    // Без подписки сервер останется со старым токеном и пуши перестанут
    // доходить.
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

    if (pb != null && userId != null) {
      try {
        await pb.collection('users').update(userId, body: {'fcm_token': ''});
      } catch (e) {
        if (kDebugMode) debugPrint('FCM token clear failed: $e');
        // Не критично — токен на сервере останется, но при логине
        // нового пользователя перезапишется новым.
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

  Future<void> _saveTokenToServer(String token) async {
    final pb = _ref.read(pocketbaseProvider);
    if (pb == null) return;
    final userId = pb.authStore.record?.id;
    if (userId == null) return;
    try {
      await pb.collection('users').update(userId, body: {'fcm_token': token});
      if (kDebugMode) debugPrint('FCM token saved for user $userId');
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token save failed: $e');
    }
  }
}

final fcmRepositoryProvider = Provider<FcmRepository>((ref) {
  return FcmRepository(ref);
});
