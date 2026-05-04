import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Тонкая обёртка над SharedPreferences. Сохраняем минимум — только то,
/// что нужно, чтобы при перезапуске не заставлять пользователя проходить
/// онбординг и выбор города заново.
class PreferencesStore {
  PreferencesStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kCityId = 'simba.cityId';
  static const _kRole = 'simba.role';
  static const _kUserId = 'simba.user.id';
  static const _kUserName = 'simba.user.name';
  static const _kUserPhone = 'simba.user.phone';
  static const _kUserPhoto = 'simba.user.photo';
  static const _kUserRating = 'simba.user.rating';
  static const _kUserReviews = 'simba.user.reviews';
  static const _kDraft = 'simba.draft.v1';

  String? get cityId => _prefs.getString(_kCityId);
  Future<void> setCityId(String? id) =>
      id == null ? _prefs.remove(_kCityId) : _prefs.setString(_kCityId, id);

  UserRole get role {
    final v = _prefs.getString(_kRole);
    return v == 'executor' ? UserRole.executor : UserRole.customer;
  }

  Future<void> setRole(UserRole r) =>
      _prefs.setString(_kRole, r == UserRole.executor ? 'executor' : 'customer');

  AppUser? get user {
    final id = _prefs.getString(_kUserId);
    if (id == null) return null;
    return AppUser(
      id: id,
      name: _prefs.getString(_kUserName) ?? '',
      phone: _prefs.getString(_kUserPhone) ?? '',
      photoPath: _prefs.getString(_kUserPhoto),
      rating: _prefs.getDouble(_kUserRating) ?? 0.0,
      reviewsCount: _prefs.getInt(_kUserReviews) ?? 0,
      cityId: _prefs.getString(_kCityId),
    );
  }

  Future<void> saveUser(AppUser u) async {
    await _prefs.setString(_kUserId, u.id);
    await _prefs.setString(_kUserName, u.name);
    await _prefs.setString(_kUserPhone, u.phone);
    if (u.photoPath != null) {
      await _prefs.setString(_kUserPhoto, u.photoPath!);
    } else {
      await _prefs.remove(_kUserPhoto);
    }
    await _prefs.setDouble(_kUserRating, u.rating);
    await _prefs.setInt(_kUserReviews, u.reviewsCount);
  }

  Future<void> clearUser() async {
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kUserName);
    await _prefs.remove(_kUserPhone);
    await _prefs.remove(_kUserPhoto);
    await _prefs.remove(_kUserRating);
    await _prefs.remove(_kUserReviews);
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
