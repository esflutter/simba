import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../features/create_order/order_draft.dart';
import '../../features/reviews/reviews_providers.dart';
import '../mock/app_state.dart';
import '../models/models.dart';
import 'categories_repository.dart';
import 'cities_repository.dart';
import 'dadata_client.dart';
import 'fcm_repository.dart';
import 'order_responses_repository.dart';
import 'orders_repository.dart';
import 'pocketbase_client.dart';
import 'reviews_repository.dart';
import 'users_repository.dart';

/// Результат SMS-операции. Mobile Authorization (SMS Aero SDK) ввела новые
/// поля, см. документацию на эндпоинты `/api/auth/sms/{send,status,verify}`:
/// - [sessionId] возвращается из `/send`, используется в дальнейших вызовах.
/// - [status] промежуточный статус Mobile ID-сессии:
///   `pending` (SIM-PUSH в процессе), `otp_required` (показать 4-значное поле),
///   `verified` (успех — токен PB уже сохранён), `rejected` (юзер отказал).
class AuthResult {
  const AuthResult({
    required this.ok,
    this.errorCode,
    this.lockedUntil,
    this.retryAfter,
    this.isNewUser = false,
    this.sessionId,
    this.status,
  });

  /// Успех — токен сохранён, либо SMS-сессия принята к обработке.
  final bool ok;

  /// Машинно-читаемый код ошибки: `rate_limited`, `phone_unavailable`,
  /// `sms_provider_failed`, `code_invalid`, `code_expired`, `phone_locked`,
  /// `session_expired`, `session_consumed`, `phone_mismatch`, `rejected`,
  /// `network`, `unknown`.
  final String? errorCode;

  /// До какого момента телефон заблокирован (для `phone_locked`).
  final DateTime? lockedUntil;

  /// Сколько секунд подождать перед повтором.
  final int? retryAfter;

  /// Бэк отметил, что юзер только что создан (meta.is_new).
  final bool isNewUser;

  /// session_id Mobile Authorization. Возвращается из `/send`, нужен для
  /// последующих `/status` и `/verify` запросов.
  final String? sessionId;

  /// Текущий статус сессии: pending/otp_required/verified/rejected.
  /// Используется UI слоем для маршрутизации между SIM-PUSH ожиданием и
  /// формой ввода 4-значного кода.
  final String? status;
}

class AuthRepository {
  AuthRepository(this._pb, this._ref);

  final PocketBase? _pb;
  final Ref _ref;

  bool get isLive => _pb != null;

  /// Таймаут на сетевые запросы к кастомным эндпоинтам OTP.
  static const _httpTimeout = Duration(seconds: 10);

  /// Запросить SMS-сессию. В live-режиме возвращает [AuthResult] с
  /// `sessionId` и `status`. На моках — просто ok=true (UI пойдёт сразу
  /// на форму ввода 4-цифр, без waiting-экрана).
  Future<bool> sendOtp(String phone) async {
    final res = await sendOtpDetailed(phone);
    return res.ok;
  }

  /// Расширенный вариант [sendOtp]. Стартует Mobile Authorization сессию:
  /// бэк дёргает SMS Aero `/api/token` + `/session/init` + `/session/start`,
  /// возвращает `session_id` для последующего поллинга/верификации.
  Future<AuthResult> sendOtpDetailed(String phone) async {
    if (!isLive) return const AuthResult(ok: true, status: 'otp_required');
    final pb = _pb!;
    final http.Response resp;
    try {
      resp = await sendWithSharedClient(
        (c) => c
            .post(
              Uri.parse('${pb.baseURL}/api/auth/sms/send'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'phone': phone}),
            )
            .timeout(_httpTimeout),
      );
    } on TimeoutException {
      return const AuthResult(ok: false, errorCode: 'network');
    } catch (_) {
      return const AuthResult(ok: false, errorCode: 'network');
    }
    final json = _safeJson(resp.body);
    if (resp.statusCode == 200 && json != null) {
      return AuthResult(
        ok: true,
        sessionId: json['session_id']?.toString(),
        status: json['status']?.toString() ?? 'pending',
      );
    }
    final retryAfter = _readRetryAfterSeconds(json);
    switch (resp.statusCode) {
      case 429:
        return AuthResult(
          ok: false,
          errorCode: 'rate_limited',
          retryAfter: retryAfter,
        );
      case 403:
        return const AuthResult(ok: false, errorCode: 'phone_unavailable');
      case 502:
        return AuthResult(
          ok: false,
          errorCode: 'sms_provider_failed',
          retryAfter: retryAfter,
        );
      default:
        return const AuthResult(ok: false, errorCode: 'unknown');
    }
  }

  /// Поллинг статуса Mobile Authorization сессии. Возвращает текущий статус;
  /// на `verified` (Mobile ID SIM-PUSH сработал без OTP) автоматически
  /// сохраняет PB JWT в authStore и возвращает `ok=true, isNewUser=…`.
  Future<AuthResult> pollMidStatus(String sessionId) async {
    if (!isLive) return const AuthResult(ok: false, errorCode: 'mock_no_poll');
    final pb = _pb!;
    final http.Response resp;
    try {
      resp = await sendWithSharedClient(
        (c) => c
            .post(
              Uri.parse('${pb.baseURL}/api/auth/sms/status'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session_id': sessionId}),
            )
            .timeout(_httpTimeout),
      );
    } on TimeoutException {
      return const AuthResult(ok: false, errorCode: 'network');
    } catch (_) {
      return const AuthResult(ok: false, errorCode: 'network');
    }
    final json = _safeJson(resp.body);
    if (resp.statusCode == 200 && json != null) {
      // Если есть token+record — это финальный verified-ответ (бэк уже
      // сделал siteverify + recordAuthResponse).
      if (json['token'] != null && json['record'] != null) {
        return _consumeAuthEnvelope(json, isFreshLogin: true);
      }
      final status = json['status']?.toString() ?? 'pending';
      return AuthResult(ok: true, status: status, sessionId: sessionId);
    }
    final retryAfter = _readRetryAfterSeconds(json);
    if (resp.statusCode == 410) {
      return const AuthResult(ok: false, errorCode: 'session_expired');
    }
    if (resp.statusCode == 429) {
      return AuthResult(
        ok: false,
        errorCode: 'rate_limited',
        retryAfter: retryAfter,
      );
    }
    if (resp.statusCode == 404) {
      return const AuthResult(ok: false, errorCode: 'session_not_found');
    }
    return const AuthResult(ok: false, errorCode: 'network');
  }

  /// Нормализация времени ожидания к секундам.
  /// Бэк возвращает `retry_in_minutes` или `retry_after_seconds`.
  int? _readRetryAfterSeconds(Map<String, dynamic>? json) {
    if (json == null) return null;
    final secs = (json['retry_after_seconds'] as num?)?.toInt();
    if (secs != null) return secs;
    final mins = (json['retry_in_minutes'] as num?)?.toInt();
    if (mins != null) return mins * 60;
    final legacy = (json['retry_after'] as num?)?.toInt();
    return legacy;
  }

  /// Проверить введённый OTP. В live-режиме передаём `sessionId+code` (4
  /// цифры), на моках — `phone+code` (произвольный 4-значный кроме `0000`).
  Future<bool> verifyOtp({
    String? sessionId,
    String? phone,
    required String code,
  }) async {
    final res = await verifyOtpDetailed(
      sessionId: sessionId,
      phone: phone,
      code: code,
    );
    return res.ok;
  }

  /// Расширенный вариант [verifyOtp]. Отправляет 4-значный OTP-код в SMS
  /// Aero через наш бэк (`/api/auth/sms/verify`), который проксирует
  /// `/api/session/{id}/otp` → `siteverify` → выдаёт PB JWT.
  Future<AuthResult> verifyOtpDetailed({
    String? sessionId,
    String? phone,
    required String code,
  }) async {
    if (!isLive) {
      if (code == '0000' || code.isEmpty) {
        return const AuthResult(ok: false, errorCode: 'code_invalid');
      }
      if (phone == null || phone.isEmpty) {
        return const AuthResult(ok: false, errorCode: 'invalid_input');
      }
      _ref.read(appControllerProvider.notifier).completeAuth(phone: phone);
      return const AuthResult(ok: true, isNewUser: true);
    }
    if (sessionId == null || sessionId.isEmpty) {
      return const AuthResult(ok: false, errorCode: 'invalid_input');
    }
    final pb = _pb!;
    final http.Response resp;
    try {
      resp = await sendWithSharedClient(
        (c) => c
            .post(
              Uri.parse('${pb.baseURL}/api/auth/sms/verify'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session_id': sessionId, 'code': code}),
            )
            .timeout(_httpTimeout),
      );
    } on TimeoutException {
      return const AuthResult(ok: false, errorCode: 'network');
    } catch (_) {
      return const AuthResult(ok: false, errorCode: 'network');
    }
    final json = _safeJson(resp.body);
    if (resp.statusCode != 200) {
      return _mapVerifyError(resp.statusCode, json);
    }
    if (json == null) {
      return const AuthResult(ok: false, errorCode: 'unknown');
    }
    return _consumeAuthEnvelope(json, isFreshLogin: true);
  }

  /// Парсит стандартный PB auth-envelope `{token, record, meta}`, сохраняет
  /// токен в authStore, зеркалит в AppController, возвращает AuthResult.
  ///
  /// `isFreshLogin` = `true` для путей verifyOtpDetailed / pollMidStatus —
  /// юзер ТОЛЬКО ЧТО ввёл код. В этом случае локально выбранный город
  /// приоритетнее серверного: его перенесём в users.city PATCH-ом.
  /// `false` (по умолчанию) — для silent tryRefreshAuth на старте: тут
  /// сервер источник правды, локальный город не пушим, чтобы не
  /// перетирать многодевайсные изменения.
  AuthResult _consumeAuthEnvelope(
    Map<String, dynamic> json, {
    bool isFreshLogin = false,
  }) {
    if (_pb == null) {
      return const AuthResult(ok: false, errorCode: 'no_backend');
    }
    final pb = _pb;
    final token = json['token']?.toString();
    final userMap = (json['record'] as Map?)?.cast<String, dynamic>() ??
        (json['user'] as Map?)?.cast<String, dynamic>();
    if (token == null || userMap == null) {
      return const AuthResult(ok: false, errorCode: 'unknown');
    }
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>();
    final isNew = meta?['is_new'] == true;

    final record = RecordModel.fromJson(userMap);
    pb.authStore.save(token, record);

    final photoFilename = record.getStringValue('photo');
    final photoUrl = photoFilename.isEmpty
        ? null
        : pb.files.getUrl(record, photoFilename).toString();
    final cityId = record.getStringValue('city');
    // Phone приходит в meta auth-ответа: бэк добавляет его в meta при
    // recordAuthResponse (см. helpers.js ensureUserAndAuth). В email phone
    // не светим — там анонимизированный uid (`<uid>@simba.local`).
    //
    // ВАЖНО: authRefresh() (см. tryRefreshAuth) НЕ возвращает meta — он
    // просто рефрешит token. В этом случае meta?['phone'] == null, и без
    // fallback'а на сохранённое значение телефон сбрасывался бы в пустую
    // строку на каждый рестарт приложения. Берём из текущего AppController.
    String phone = (meta?['phone'] as String?) ?? '';
    if (phone.isEmpty) {
      final existing = _ref.read(appControllerProvider).user?.phone;
      if (existing != null && existing.isNotEmpty) phone = existing;
    }

    // Город: на свежем логине приоритет у того, который юзер выбрал
    // локально на /city ПЕРЕД авторизацией. Если он выбрал Казань и
    // логинится в аккаунт, где на сервере была Москва — оставляем
    // Казань и тихо обновляем серверную запись. На silent refresh
    // (tryRefreshAuth) наоборот — сервер источник правды, чтобы
    // изменения с другого устройства подхватывались.
    //
    // Защита: если pendingCitySync не null, в полёте PATCH /city от
    // setCity — вообще не трогаем.
    final ctrl = _ref.read(appControllerProvider.notifier);
    final localCityId = _ref.read(appControllerProvider).selectedCityId;
    final hasLocal = localCityId != null && localCityId.isNotEmpty;
    if (ctrl.pendingCitySync == null) {
      if (!hasLocal && cityId.isNotEmpty) {
        ctrl.setCity(cityId);
      } else if (isFreshLogin &&
          hasLocal &&
          localCityId != cityId) {
        // Свежий логин: пушим локальный выбор на сервер
        // fire-and-forget. Ошибки не критичны — следующий setCity
        // повторит попытку.
        //
        // ВАЖНО: unawaited + catchError. Внешний try/catch не ловит
        // ошибку этого Future — он завершается синхронно ДО того, как
        // запрос реально выполнится. Без catchError исключение через
        // 10 сек таймаута всплывает в Zone-handler и в release-сборках
        // даёт crash-log.
        unawaited(pb
            .collection('users')
            .update(record.id, body: {'city': localCityId})
            .timeout(const Duration(seconds: 10))
            .catchError((Object _) {
          // Не блокируем auth, тихо игнорируем. RecordModel-возврат для
          // совместимости с типом возвращаемого Future.
          return record;
        }));
      } else if (!isFreshLogin && cityId.isNotEmpty && cityId != localCityId) {
        // Silent refresh: сервер обновился (другой девайс?). Принимаем
        // серверное значение, чтобы оба девайса показывали одно и то же.
        ctrl.setCity(cityId);
      }
    }

    final user = AppUser(
      id: record.id,
      name: record.getStringValue('name'),
      phone: phone,
      photoPath: photoUrl,
      rating: record.getDoubleValue('rating_as_executor'),
      reviewsCount: record.getIntValue('reviews_count_as_executor'),
      ratingAsCustomer: record.getDoubleValue('rating_as_customer'),
      reviewsCountAsCustomer: record.getIntValue('reviews_count_as_customer'),
      ratingAsExecutor: record.getDoubleValue('rating_as_executor'),
      reviewsCountAsExecutor: record.getIntValue('reviews_count_as_executor'),
      cityId: cityId.isEmpty ? null : cityId,
      hasTools: record.getBoolValue('has_tools'),
      hasTransport: record.getBoolValue('has_transport'),
    );
    _ref.read(appControllerProvider.notifier).completeAuthRemote(user);

    // Роль и «Готов помочь»: на свежем логине берём серверное значение
    // `is_active_executor`. Поле живёт в users_private (клиенту напрямую
    // не видно), бэк прокидывает его в meta auth-ответа (см. helpers.js
    // ensureUserAndAuth). Раньше клиент пытался читать его из record —
    // там его никогда не было, синхронизация тихо не работала.
    //
    // logout локально сбрасывает state.role на customer — без серверной
    // подтяжки сценарий «выйти-войти на том же телефоне» терял бы
    // исторический «Готов помочь». Для новых юзеров серверное значение
    // по умолчанию false → ничего не ломаем; роль им выставит
    // /role_picker после verifyOtp (setRole пушит на сервер сам).
    //
    // На silent refresh (cold start) серверный флаг в meta НЕ приходит
    // (authRefresh не зовёт нашу ручку). В этом случае берём
    // соответствующее состояние из ранее сохранённого state.role и
    // одновременно синхронизируем `executorActive` (он на cold-start
    // всегда сбрасывался в false, из-за чего тумблер «Готов помочь»
    // показывался выключенным даже когда сервер считал юзера активным).
    final metaIsActiveExecutor = meta?['is_active_executor'];
    if (isFreshLogin && metaIsActiveExecutor is bool) {
      final serverRole =
          metaIsActiveExecutor ? UserRole.executor : UserRole.customer;
      final localRole = _ref.read(appControllerProvider).role;
      if (localRole != serverRole) {
        ctrl.adoptRoleFromServer(serverRole);
      }
      // executorActive (флаг «Готов помочь сейчас») тоже выравниваем
      // под серверный — без этого тумблер в UI и серверный сегмент
      // push'ей могут рассинхрониться: юзер закрыл приложение в
      // «онлайн», сервер шлёт ему пуши, а локально тумблер OFF.
      ctrl.adoptExecutorActiveFromServer(metaIsActiveExecutor);
    }
    // На silent refresh executorActive НЕ трогаем. Раньше тут стоял
    // ctrl.adoptExecutorActiveFromServer(localRole == executor), который
    // на каждом cold-start заново включал тумблер у юзеров с role=executor —
    // даже если юзер на другом устройстве сам выключил «Готов помочь».
    // executorActive хранится локально в SharedPreferences и переживает
    // cold-start; синхронизация с сервером по-настоящему нужна только при
    // fresh login (на новом устройстве/после reinstall).
    // Регистрируем FCM-токен на сервере. Делаем fire-and-forget: запрос
    // permission на iOS показывает системный диалог (200-500 мс), а ждать
    // его в auth-флоу нет смысла — авторизация прошла, дальше пусть
    // токен дописывается в фоне. Если упало (нет интернета, permission
    // denied) — следующий запуск приложения попробует снова.
    debugPrint('[FCM] auth: scheduling registerForCurrentUser');
    unawaited(_ref.read(fcmRepositoryProvider).registerForCurrentUser());
    return AuthResult(ok: true, isNewUser: isNew, status: 'verified');
  }

  AuthResult _mapVerifyError(int status, Map<String, dynamic>? json) {
    final code = (json?['error'] ?? json?['code'])?.toString();
    final lockedUntilStr =
        (json?['until'] ?? json?['locked_until'])?.toString();
    final lockedUntil =
        (lockedUntilStr != null) ? DateTime.tryParse(lockedUntilStr) : null;
    final retryAfter = _readRetryAfterSeconds(json);
    if (status == 400 && code == 'code_invalid') {
      return const AuthResult(ok: false, errorCode: 'code_invalid');
    }
    if (status == 400 && code == 'code_expired') {
      return const AuthResult(ok: false, errorCode: 'code_expired');
    }
    if (status == 400 && code == 'invalid_input') {
      return const AuthResult(ok: false, errorCode: 'invalid_input');
    }
    if (status == 410) {
      // session_expired или session_consumed
      return AuthResult(
        ok: false,
        errorCode: code ?? 'session_expired',
      );
    }
    if (status == 403 && code == 'phone_mismatch') {
      return const AuthResult(ok: false, errorCode: 'phone_mismatch');
    }
    if (status == 404) {
      return const AuthResult(ok: false, errorCode: 'session_not_found');
    }
    if ((status == 423 || status == 429) && code == 'phone_locked') {
      return AuthResult(
        ok: false,
        errorCode: 'phone_locked',
        lockedUntil: lockedUntil,
        retryAfter: retryAfter,
      );
    }
    if (status == 429) {
      return AuthResult(
        ok: false,
        errorCode: 'rate_limited',
        retryAfter: retryAfter,
      );
    }
    return const AuthResult(ok: false, errorCode: 'unknown');
  }

  Map<String, dynamic>? _safeJson(String body) {
    if (body.isEmpty) return null;
    try {
      final v = jsonDecode(body);
      return v is Map ? v.cast<String, dynamic>() : null;
    } catch (e) {
      // На 502/Cloudflare-челлендже бэк отвечает HTML вместо JSON.
      // В release-сборку логируем только сам факт ошибки, без `e`: текст
      // исключения от http может содержать URL запроса с query-параметрами
      // и попасть в logcat, где его читают сторонние приложения.
      if (kDebugMode) {
        debugPrint('[auth_repository] _safeJson parse failed: $e');
      }
      return null;
    }
  }

  /// Logout — очистка PB-сессии и мок-стейта. Инвалидирует auth-зависимые
  /// провайдеры, чтобы при следующем входе данные не «протекли».
  Future<void> logout() async {
    final pb = _pb;
    // ВАЖНО: чистим FCM-токен ДО pb.authStore.clear(), иначе fcmRepository
    // потеряет доступ к userId и не сможет очистить fcm_token на сервере.
    // Иначе следующий владелец того же устройства начнёт получать пуши,
    // адресованные предыдущему юзеру.
    if (pb != null && pb.authStore.isValid) {
      try {
        await _ref
            .read(fcmRepositoryProvider)
            .clearForCurrentUser()
            .timeout(const Duration(seconds: 3));
      } catch (_) {/* не блокируем logout */}
    }
    if (pb != null) {
      // Перед очисткой токена снимаем флаг is_active_executor на бэке,
      // иначе сегмент push-рассылки «new_order_nearby» продолжит включать
      // этого юзера до естественного истечения TTL координат (см. cron
      // cleanup-stale-locations, 6 часов). Если запрос упал — не блокируем
      // logout, в худшем случае юзер ещё несколько часов получит push'и
      // (но без открытого приложения они всё равно не дойдут до UI).
      if (pb.authStore.isValid) {
        try {
          // sendWithSharedClient — если устройство после долгого сна
          // имеет закрытый сокет, обёртка сама пересоздаст клиент.
          // Без неё logout сразу после wake-up иногда оставлял флаг
          // is_active_executor включённым на сервере.
          await sendWithSharedClient(
            (c) => c.post(
              Uri.parse('${pb.baseURL}/api/me/executor-status'),
              headers: {
                // Bearer-префикс обязателен: PB 0.22+ строго парсит схему
                // авторизации, без `Bearer ` запрос приходит на сервер как
                // анонимный (e.auth=null). В executor-status это значило, что
                // флаг is_active_executor никогда не сбрасывался в false при
                // logout — пуш-сегмент держал юзера активным до естественного
                // истечения TTL координат.
                'Authorization': 'Bearer ${pb.authStore.token}',
                'Content-Type': 'application/json',
              },
              body: '{"is_active": false}',
            ).timeout(const Duration(seconds: 3)),
          );
        } catch (_) {/* не блокируем logout */}
      }
      pb.authStore.clear();
      await Future<void>.delayed(Duration.zero);
    }
    _ref.read(appControllerProvider.notifier).logout();
    // Сбрасываем dedup-маркер силент-рефреша. Без сброса следующий логин
    // другим аккаунтом в течение 30 секунд после logout-а пропустит
    // полноценный refresh — _lastSuccessfulRefreshAt всё ещё «свежий» по
    // часам, и tryRefreshAuth вернёт true без сетевого вызова. Это
    // безвредно само по себе (новый authStore уже валиден), но даёт
    // мизерный шанс на путаницу при отладке.
    _lastSuccessfulRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      _ref.invalidate(myOrdersStreamProvider);
      _ref.invalidate(myExecutorOrdersProvider);
      _ref.invalidate(feedOrdersProvider);
      _ref.invalidate(contactPhoneProvider);
      _ref.invalidate(reviewsForUserProvider);
      _ref.invalidate(reviewsByOrderProvider);
      // Кэш «по каким заказам я уже оставил отзыв» сделан НЕ-autoDispose
      // (одна выборка для обоих табов истории). Без явного invalidate
      // на logout — после смены пользователя на том же устройстве
      // кнопка «Оставить отзыв» рисуется/прячется по заказам прошлого
      // юзера, пока не пройдёт первый запрос свежего списка отзывов.
      _ref.invalidate(myReviewedOrderIdsProvider);
      _ref.read(orderDraftProvider.notifier).reset();
      _ref.invalidate(reviewsRepositoryProvider);
      _ref.invalidate(ordersRepositoryProvider);
      _ref.invalidate(orderResponsesRepositoryProvider);
      _ref.invalidate(usersRepositoryProvider);
      _ref.invalidate(dadataClientProvider);
      // Справочники городов и категорий — публичные данные, но за время
      // сессии админ мог добавить/выключить город или категорию.
      // Без инвалидации новый юзер на этом устройстве видит старый
      // список до полного перезапуска приложения.
      _ref.invalidate(citiesProvider);
      _ref.invalidate(categoriesProvider);
    } catch (_) {
      // ok если провайдер не зарегистрирован в текущем scope.
    }
  }

  /// Текущий PB-юзер (или null).
  RecordModel? get currentUser => _pb?.authStore.record;

  /// Бутстрап-проверка валидности сохранённого токена при старте приложения.
  /// При успехе зеркалит данные юзера из `pb.authStore.record` в AppController,
  /// иначе splash на cold-start увидит `isValid==true` при пустом `state.user`
  /// и погонит на онбординг при валидной сессии.
  // Дедуп частых вызовов tryRefreshAuth. Резюм-обработчики на нескольких
  // экранах (feed, my_orders, history, sms_code, splash) дёргают refresh
  // на каждый перевод приложения в foreground — если пользователь часто
  // переключается между приложениями (или Android посылает фейковый
  // resumed на изменение системных настроек), это лишний трафик и шум
  // в логах. Если прошло меньше 30 секунд с последнего успешного
  // refresh — возвращаем true без сетевого вызова. На single-flight это
  // не влияет (тот защищает от параллельных запросов в одну секунду).
  DateTime _lastSuccessfulRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kRefreshDedupWindow = Duration(seconds: 30);

  Future<bool> tryRefreshAuth() async {
    final pb = _pb;
    if (pb == null || !pb.authStore.isValid) {
      // PB-токена нет, а state.user может остаться в prefs от прошлой
      // сессии (например, при переустановке APK поверх — токен хранится
      // отдельно от prefs и иногда пропадает, а user-запись в prefs
      // остаётся). Это ломает редирект: splash видит state.user != null
      // и ведёт сразу в /home, где первый же запрос ловит 401. Чистим
      // state.user, чтобы редирект корректно отправил на /auth/phone.
      try {
        final state = _ref.read(appControllerProvider);
        if (state.user != null) {
          _ref.read(appControllerProvider.notifier).logout();
        }
      } catch (_) {}
      return false;
    }
    // Дедуп: если только что (< 30 сек) уже сделали refresh — пропускаем.
    if (DateTime.now().difference(_lastSuccessfulRefreshAt) <
        _kRefreshDedupWindow) {
      return true;
    }
    try {
      // 6с синхронизировано с обёрткой в splash_screen — иначе внутренний
      // таймаут срабатывал раньше, и splash думал что refresh не дошёл,
      // хотя он мог ещё успеть.
      //
      // Идём через общий single-flight — иначе splash и параллельные
      // провайдеры на главном экране могут одновременно запустить два
      // refresh с одним токеном, и поздний ответ затрёт свежий.
      await pb.refreshAuthSingleFlight().timeout(const Duration(seconds: 6));
      _lastSuccessfulRefreshAt = DateTime.now();
      final record = pb.authStore.record;
      if (record != null) {
        // Зеркалим record в AppController.state.user тем же путём, что и
        // обычный verify-flow — чтобы поля photoUrl/cityId/rating сошлись.
        _consumeAuthEnvelope({
          'token': pb.authStore.token,
          'record': record.toJson(),
        });
      }
      return true;
    } on ClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        pb.authStore.clear();
        await Future<void>.delayed(Duration.zero);
        try {
          _ref.read(appControllerProvider.notifier).logout();
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(pocketbaseProvider), ref);
});
