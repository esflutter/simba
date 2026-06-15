import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';

/// Лог только в debug. В release не светим в logcat содержимое пуша и
/// тексты ошибок — там бывают id заказов, маршрут перехода и тип
/// события. (`[push] no route in payload` печатал весь data-объект.)
void _pushLog(String msg) {
  if (kDebugMode) debugPrint(msg);
}

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

  // Глубокая ссылка из пуша, по которому открыли УБИТОЕ приложение. На
  // холодном старте мы ещё на заставке; если перейти сразу — целевой экран
  // ляжет ПОВЕРХ заставки, и «назад» вернёт на неё (крутящийся спиннер).
  // Поэтому откладываем ссылку и применяем её из заставки уже ПОСЛЕ
  // перехода на главную — тогда стек: главная → заказ, «назад» работает.
  Map<String, dynamic>? _pendingColdStart;

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
      _pushLog('[push] setForegroundNotificationPresentationOptions: $e');
    }

    final messaging = FirebaseMessaging.instance;

    // 1) Пуш, по которому открыли убитое приложение. null — обычный запуск.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null && !_initialHandled) {
        _initialHandled = true;
        final router = _ref.read(routerProvider);
        final onSplash =
            router.routerDelegate.currentConfiguration.uri.path == '/splash';
        if (onSplash) {
          // Ещё на заставке — отдаём ссылку ей: она применит её ПОСЛЕ
          // перехода на главную (стек главная → заказ, «назад» работает).
          // Раньше тут был scheduleMicrotask с push прямо поверх заставки,
          // и «назад» с заказа возвращал на крутящийся спиннер заставки.
          _pendingColdStart = initial.data;
        } else {
          // Заставка уже ушла (редкая гонка) — роутим как обычно.
          scheduleMicrotask(() => _routeFromMessage(initial));
        }
      }
    } catch (e) {
      _pushLog('[push] getInitialMessage failed: $e');
    }

    // 2) Тап по системному пушу, пока приложение в фоне.
    // onMessageOpenedApp — статический stream класса.
    _openedSub?.cancel();
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      _routeFromMessage,
      onError: (Object e) {
        _pushLog('[push] onMessageOpenedApp error: $e');
      },
    );

    // 3) Пуш пришёл когда приложение открыто. Сами рисуем баннер —
    // иначе на Android юзер вообще ничего не увидит.
    _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
      onError: (Object e) {
        _pushLog('[push] onMessage error: $e');
      },
    );
  }

  void dispose() {
    _openedSub?.cancel();
    _openedSub = null;
    _messageSub?.cancel();
    _messageSub = null;
  }

  /// Применить отложенную глубокую ссылку холодного старта. Зовётся
  /// заставкой ПОСЛЕ её перехода на главный экран — тогда целевой экран
  /// ложится поверх главной, и «назад» ведёт на главную, а не на заставку.
  /// Если ничего не отложено — ничего не делает.
  void applyPendingColdStart() {
    final data = _pendingColdStart;
    _pendingColdStart = null;
    if (data != null && data.isNotEmpty) _routeFromData(data);
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
      _pushLog('[push] local tap payload parse failed: $e');
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
      _pushLog('[push] local show failed: $e');
    }
  }

  void _routeFromMessage(RemoteMessage message) {
    _routeFromData(message.data);
  }

  void _routeFromData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final target = _resolveRoute(data);
    if (target == null) {
      _pushLog('[push] no route in payload: $data');
      return;
    }
    try {
      final router = _ref.read(routerProvider);
      // Текущий маршрут — чтобы не плодить дубликаты при повторном тапе по
      // пушу, когда нужный экран уже открыт (иначе копии копятся, и «назад»
      // приходится жать несколько раз).
      // Сравниваем только ПУТЬ, без query: экран заказа из ленты/«моих»/
      // истории всегда открыт с ?mode=..., а цель пуша — без него, поэтому
      // сравнение полного адреса никогда не совпадало и дубликаты копились.
      final current = router.routerDelegate.currentConfiguration.uri.path;
      if (current == target.route) return;
      // Для вложенного экрана откликов сначала кладём в стек экран заказа,
      // потом сами отклики — иначе при открытии из «холодного» пуша кнопка
      // «назад» с экрана откликов сразу выкидывала на главный, минуя заказ.
      // Если мы уже на экране-родителе — повторно его не кладём.
      if (target.parent != null && current != target.parent) {
        router.push(target.parent!);
      }
      router.push(target.route);
    } catch (e) {
      _pushLog('[push] navigation failed for ${target.route}: $e');
    }
  }

  /// Строим маршрут САМИ из `type` + `order_id`, не доверяя сырому
  /// `data.route` из пуша. Сервер своё поле route кладёт, но push-payload
  /// приходит снаружи — слепо роутить по строке из него небезопасно
  /// (теоретически можно увести в неожиданный экран). order_id проверяем
  /// на формат id PocketBase (15 строчных букв/цифр).
  _PushTarget? _resolveRoute(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final rawId = data['order_id']?.toString() ?? '';
    final orderId =
        RegExp(r'^[a-z0-9]{15}$').hasMatch(rawId) ? rawId : null;

    switch (type) {
      case 'response_received':
        // Вложенный экран — достраиваем стек через parent.
        return orderId == null
            ? null
            : _PushTarget('/order/$orderId/responses',
                parent: '/order/$orderId');
      case 'order_accepted':
      case 'order_cancelled':
      case 'work_done':
      case 'payment_received':
      case 'review_request':
        return orderId == null ? null : _PushTarget('/order/$orderId');
      case 'review_received':
        return _PushTarget('/profile/reviews');
      default:
        return null;
    }
  }
}

/// Маршрут перехода по тапу на пуш. `parent` — экран, который надо
/// положить в стек ПЕРЕД целевым, чтобы кнопка «назад» работала
/// (для вложенных экранов вроде откликов на заказ).
class _PushTarget {
  const _PushTarget(this.route, {this.parent});
  final String route;
  final String? parent;
}

final pushHandlerProvider = Provider<PushHandler>((ref) {
  final handler = PushHandler(ref);
  ref.onDispose(handler.dispose);
  return handler;
});
