import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';

/// Обработчик push-уведомлений — отображение баннера в foreground и
/// открытие нужного экрана при тапе.
///
/// Сценарии доставки тапа во Flutter:
///   * **terminated/cold-start**: приложение убито, юзер тапает по
///     пушу. Flutter поднимается, мы дёргаем `getInitialMessage()`.
///   * **background**: приложение свёрнуто, юзер тапает по пушу в
///     шторке. Доходит через `FirebaseMessaging.onMessageOpenedApp`.
///   * **foreground**: приложение открыто. Android по умолчанию НЕ
///     рисует баннер сам — пуш приходит только в `onMessage`. Мы
///     показываем локальное уведомление через
///     `flutter_local_notifications`, чтобы юзер увидел баннер. При
///     тапе на этот баннер срабатывает наш собственный callback.
class PushHandler {
  PushHandler(this._ref);
  final Ref _ref;

  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  bool _initialHandled = false;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  /// id канала уведомлений на Android. Один общий канал «default» —
  /// без приоритезации по типу пуша. Если в будущем нужно будет
  /// разделить (например, «срочные» отдельно от «информационных») —
  /// добавим второй channel.
  static const _androidChannelId = 'simba_default';
  static const _androidChannelName = 'SimbA — уведомления';
  static const _androidChannelDescription =
      'Отклики, выбор исполнителя, отзывы и другие события заказа';

  Future<void> init() async {
    await _initLocalNotifications();

    // На iOS просим FCM сам показывать баннер в foreground — это
    // встроенная фича. На Android этот вызов безопасен (no-op).
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[push] setForegroundNotificationPresentationOptions: $e');
    }

    final messaging = FirebaseMessaging.instance;

    // 1) Пуш, по которому открыли убитое приложение. null — обычный запуск.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null && !_initialHandled) {
        _initialHandled = true;
        // Откладываем переход — чтобы GoRouter сначала отработал
        // первичный redirect (splash → home/auth), и наш push-переход
        // лёг на правильный стек, а не на /splash.
        scheduleMicrotask(() => _routeFromMessage(initial));
      }
    } catch (e) {
      debugPrint('[push] getInitialMessage failed: $e');
    }

    // 2) Тап по системному пушу, пока приложение в фоне.
    // onMessageOpenedApp — статический stream класса.
    _openedSub?.cancel();
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      _routeFromMessage,
      onError: (Object e) {
        debugPrint('[push] onMessageOpenedApp error: $e');
      },
    );

    // 3) Пуш пришёл когда приложение открыто. Сами рисуем баннер —
    // иначе на Android юзер вообще ничего не увидит.
    _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
      onError: (Object e) {
        debugPrint('[push] onMessage error: $e');
      },
    );
  }

  void dispose() {
    _openedSub?.cancel();
    _openedSub = null;
    _messageSub?.cancel();
    _messageSub = null;
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // Канал на Android 8+. Без этого system отбрасывает уведомления.
    if (Platform.isAndroid) {
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: _androidChannelDescription,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }
  }

  /// Юзер тапнул по локальному баннеру (показанному, когда приложение
  /// было в foreground). В payload лежит JSON оригинальных data из
  /// RemoteMessage — достаём и роутим.
  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = (jsonDecode(payload) as Map).cast<String, dynamic>();
      _routeFromData(data);
    } catch (e) {
      debugPrint('[push] local tap payload parse failed: $e');
    }
  }

  /// Показывает баннер для пуша, который пришёл при открытом приложении.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;
    final title = notif.title ?? '';
    final body = notif.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final data = message.data;
    String? payload;
    try {
      payload = jsonEncode(data);
    } catch (_) {
      payload = null;
    }

    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'SimbA',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // Уникальный id — иначе локальный плагин «замещает» предыдущее
    // уведомление с тем же id. millisecondsSinceEpoch гарантирует
    // уникальность в пределах разумного. Берём младшие 31 бит, чтобы
    // влезть в int32 — на Android и iOS id ограничен 32-битовым int.
    final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

    try {
      await _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[push] local show failed: $e');
    }
  }

  void _routeFromMessage(RemoteMessage message) {
    _routeFromData(message.data);
  }

  void _routeFromData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final route = _resolveRoute(data);
    if (route == null || route.isEmpty) {
      debugPrint('[push] no route in payload: $data');
      return;
    }
    try {
      _ref.read(routerProvider).push(route);
    } catch (e) {
      debugPrint('[push] navigation failed for $route: $e');
    }
  }

  /// `data.route` — главный источник правды (сервер кладёт готовую ссылку).
  /// Fallback по типу — на случай, если сервер не положит route
  /// (старая нотификация / новый тип / ошибка енквью).
  String? _resolveRoute(Map<String, dynamic> data) {
    final explicit = data['route']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final type = data['type']?.toString();
    final orderId = data['order_id']?.toString();

    switch (type) {
      case 'response_received':
        return orderId != null ? '/order/$orderId/responses' : null;
      case 'order_accepted':
      case 'order_cancelled':
      case 'work_done':
      case 'payment_received':
      case 'review_request':
        return orderId != null ? '/order/$orderId' : null;
      case 'review_received':
        return '/profile/reviews';
      default:
        return null;
    }
  }
}

final pushHandlerProvider = Provider<PushHandler>((ref) {
  final handler = PushHandler(ref);
  ref.onDispose(handler.dispose);
  return handler;
});
