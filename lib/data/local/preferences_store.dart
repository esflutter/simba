import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Тонкая обёртка над SharedPreferences. Сохраняем минимум — только то,
/// что нужно, чтобы при перезапуске не заставлять пользователя проходить
/// онбординг и выбор города заново.
///
/// Телефон пользователя (PII по 152-ФЗ) лежит в защищённом системном
/// хранилище: на Android — EncryptedSharedPreferences (AndroidX Security
/// Crypto), на iOS — Keychain. Остальные поля профиля (имя, фото, рейтинг)
/// — в обычных SharedPreferences: имя не является чувствительной PII в
/// нашей модели, фото — это URL/локальный путь, рейтинг — публичные
/// агрегированные числа.
class PreferencesStore {
  PreferencesStore._(this._prefs, this._secure, this._cachedPhone);
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  // Кэш телефона в памяти — чтобы синхронный геттер `user` не превращать
  // в async. При создании инстанса (PreferencesStore.create) читаем
  // защищённое хранилище один раз; дальше saveUser/clearUser обновляют
  // и кэш, и secure-стор.
  String? _cachedPhone;

  static const _kCityId = 'simba.cityId';
  static const _kRole = 'simba.role';
  // Флаг «этот пользователь устройства уже видел онбординг». Хранится в
  // prefs пожизненно (на уровне устройства, не аккаунта) — после logout
  // онбординг повторно НЕ показывается, юзер сразу идёт к логину.
  static const _kOnboardingSeen = 'simba.onboarding.seen';
  static const _kUserId = 'simba.user.id';
  static const _kUserName = 'simba.user.name';
  // Legacy-ключ телефона в обычных prefs. Используется ТОЛЬКО для
  // одноразовой миграции в защищённое хранилище при первом запуске
  // после обновления. После миграции запись удаляется.
  static const _kLegacyUserPhone = 'simba.user.phone';
  // Защищённый ключ телефона. Версия v2 — чтобы старые сборки с тем же
  // именем (на случай downgrade) не путали зашифрованное значение с
  // открытым текстом.
  static const _kSecurePhoneV2 = 'simba.user.phone.v2';
  static const _kUserPhoto = 'simba.user.photo';
  // Legacy-поля (соответствуют ratingAsExecutor/reviewsCountAsExecutor —
  // см. модель AppUser). Оставлены для обратной совместимости со старыми
  // prefs (юзер обновился — данные не пропали), пишутся параллельно с
  // ratingE/reviewsE.
  static const _kUserRating = 'simba.user.rating';
  static const _kUserReviews = 'simba.user.reviews';
  // Раздельные рейтинги по ролям. После cold-start без этих ключей
  // ratingAsCustomer/ratingAsExecutor оставались бы дефолтными (0.0) —
  // профильный экран показывал бы пустой рейтинг до первого authRefresh.
  static const _kUserRatingC = 'simba.user.rating_customer';
  static const _kUserReviewsC = 'simba.user.reviews_customer';
  static const _kUserRatingE = 'simba.user.rating_executor';
  static const _kUserReviewsE = 'simba.user.reviews_executor';
  static const _kUserHasTools = 'simba.user.hasTools';
  static const _kUserHasTransport = 'simba.user.hasTransport';
  static const _kDraft = 'simba.draft.v1';

  String? get cityId => _prefs.getString(_kCityId);
  Future<void> setCityId(String? id) =>
      id == null ? _prefs.remove(_kCityId) : _prefs.setString(_kCityId, id);

  bool get onboardingSeen => _prefs.getBool(_kOnboardingSeen) ?? false;
  Future<void> setOnboardingSeen(bool v) => _prefs.setBool(_kOnboardingSeen, v);

  UserRole get role {
    final v = _prefs.getString(_kRole);
    return v == 'executor' ? UserRole.executor : UserRole.customer;
  }

  Future<void> setRole(UserRole r) =>
      _prefs.setString(_kRole, r == UserRole.executor ? 'executor' : 'customer');

  /// Создание стора с загрузкой телефона из защищённого хранилища.
  /// Делает одноразовую миграцию старого открытого ключа в secure-стор,
  /// если он остался от предыдущей версии приложения.
  static Future<PreferencesStore> create(SharedPreferences prefs) async {
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    String? phone;
    try {
      phone = await secure.read(key: _kSecurePhoneV2);
    } catch (e) {
      if (kDebugMode) debugPrint('Secure storage read failed: $e');
    }
    // Миграция: телефон из старых открытых prefs → в secure. После
    // миграции удаляем из открытых prefs.
    if ((phone == null || phone.isEmpty) &&
        prefs.containsKey(_kLegacyUserPhone)) {
      final legacy = prefs.getString(_kLegacyUserPhone);
      if (legacy != null && legacy.isNotEmpty) {
        phone = legacy;
        try {
          await secure.write(key: _kSecurePhoneV2, value: legacy);
        } catch (_) {/* secure недоступен — не блокируем старт */}
      }
      await prefs.remove(_kLegacyUserPhone);
    }
    return PreferencesStore._(prefs, secure, phone);
  }

  AppUser? get user {
    final id = _prefs.getString(_kUserId);
    if (id == null) return null;
    // Legacy-fallback: на старых prefs (до раздельных ключей) рейтинг был
    // только в _kUserRating — мапим его на ratingAsExecutor, как делает
    // _consumeAuthEnvelope в auth_repository (rating ≡ ratingAsExecutor).
    final legacyRating = _prefs.getDouble(_kUserRating) ?? 0.0;
    final legacyReviews = _prefs.getInt(_kUserReviews) ?? 0;
    return AppUser(
      id: id,
      name: _prefs.getString(_kUserName) ?? '',
      phone: _cachedPhone ?? '',
      photoPath: _prefs.getString(_kUserPhoto),
      rating: legacyRating,
      reviewsCount: legacyReviews,
      ratingAsCustomer: _prefs.getDouble(_kUserRatingC) ?? 0.0,
      reviewsCountAsCustomer: _prefs.getInt(_kUserReviewsC) ?? 0,
      ratingAsExecutor: _prefs.getDouble(_kUserRatingE) ?? legacyRating,
      reviewsCountAsExecutor: _prefs.getInt(_kUserReviewsE) ?? legacyReviews,
      cityId: _prefs.getString(_kCityId),
      hasTools: _prefs.getBool(_kUserHasTools) ?? false,
      hasTransport: _prefs.getBool(_kUserHasTransport) ?? false,
    );
  }

  Future<void> saveUser(AppUser u) async {
    await _prefs.setString(_kUserId, u.id);
    await _prefs.setString(_kUserName, u.name);
    // Телефон — в защищённое хранилище. Если запись не удалась (например,
    // на Android при сбое Keystore) — фоллбэк не делаем, телефон просто
    // не сохранится локально и при перезапуске подгрузится из auth-meta.
    if (u.phone.isNotEmpty) {
      try {
        await _secure.write(key: _kSecurePhoneV2, value: u.phone);
        _cachedPhone = u.phone;
      } catch (e) {
        if (kDebugMode) debugPrint('Secure write phone failed: $e');
      }
    } else {
      try {
        await _secure.delete(key: _kSecurePhoneV2);
      } catch (_) {}
      _cachedPhone = null;
    }
    if (u.photoPath != null) {
      await _prefs.setString(_kUserPhoto, u.photoPath!);
    } else {
      await _prefs.remove(_kUserPhoto);
    }
    await _prefs.setDouble(_kUserRating, u.rating);
    await _prefs.setInt(_kUserReviews, u.reviewsCount);
    await _prefs.setDouble(_kUserRatingC, u.ratingAsCustomer);
    await _prefs.setInt(_kUserReviewsC, u.reviewsCountAsCustomer);
    await _prefs.setDouble(_kUserRatingE, u.ratingAsExecutor);
    await _prefs.setInt(_kUserReviewsE, u.reviewsCountAsExecutor);
    await _prefs.setBool(_kUserHasTools, u.hasTools);
    await _prefs.setBool(_kUserHasTransport, u.hasTransport);
  }

  Future<void> clearUser() async {
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kUserName);
    try {
      await _secure.delete(key: _kSecurePhoneV2);
    } catch (_) {/* secure недоступен — не блокируем logout */}
    _cachedPhone = null;
    await _prefs.remove(_kUserPhoto);
    await _prefs.remove(_kUserRating);
    await _prefs.remove(_kUserReviews);
    await _prefs.remove(_kUserRatingC);
    await _prefs.remove(_kUserReviewsC);
    await _prefs.remove(_kUserRatingE);
    await _prefs.remove(_kUserReviewsE);
    await _prefs.remove(_kUserHasTools);
    await _prefs.remove(_kUserHasTransport);
    // Чистим роль (она привязана к конкретному юзеру) и черновик заказа.
    // НО cityId оставляем — это локальный выбор устройства; новый юзер
    // увидит сохранённый город (его всё равно перезапишет users.city с
    // бэка при логине, если у того юзера город уже выбран на сервере).
    // Это позволяет пропустить страницу /city после logout.
    await _prefs.remove(_kRole);
    await _prefs.remove(_kDraft);
  }

  /// Черновик создаваемого заказа в JSON. Кладём «как есть», парсит
  /// `OrderDraft.fromJson`. Версия в ключе на случай миграции схемы.
  String? get draftJson => _prefs.getString(_kDraft);
  Future<void> saveDraftJson(String json) => _prefs.setString(_kDraft, json);
  Future<void> clearDraft() => _prefs.remove(_kDraft);
}

/// Override-провайдер: реальный SharedPreferences инициализируется в main()
/// и подсовывается через ProviderScope.overrides.
final preferencesProvider = Provider<PreferencesStore>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);
