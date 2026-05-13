import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../mock/app_state.dart';
import '../models/models.dart';
import 'pocketbase_client.dart';

class AuthRepository {
  AuthRepository(this._pb, this._ref);

  final PocketBase? _pb;
  final Ref _ref;

  bool get isLive => _pb != null;

  /// Таймаут на сетевые запросы к кастомным эндпоинтам OTP.
  static const _httpTimeout = Duration(seconds: 10);

  /// Отправить OTP на телефон. На моках всегда успех (код подтверждается
  /// фиктивно — клиент принимает любой 6-значный кроме `000000`).
  Future<bool> sendOtp(String phone) async {
    if (!isLive) return true;
    final pb = _pb!;
    try {
      final resp = await http
          .post(
            Uri.parse('${pb.baseURL}/api/auth/sms/send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(_httpTimeout);
      return resp.statusCode == 200;
    } on TimeoutException {
      return false;
    }
  }

  /// Проверить OTP и получить токен. На моках принимаем любой код кроме
  /// `000000` и сразу регистрируем мок-юзера.
  Future<bool> verifyOtp({
    required String phone,
    required String code,
  }) async {
    if (!isLive) {
      if (code == '000000') return false;
      _ref.read(appControllerProvider.notifier).completeAuth(phone: phone);
      return true;
    }
    final pb = _pb!;
    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('${pb.baseURL}/api/auth/sms/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'code': code}),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      return false;
    }
    if (resp.statusCode != 200) return false;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final token = json['token']?.toString();
    final userMap = (json['user'] as Map?)?.cast<String, dynamic>();
    if (token == null || userMap == null) return false;

    // Сохраняем токен в pb.authStore. В SDK pocketbase ^0.22 правильный
    // фабричный метод — `RecordModel.fromJson` (он же распарсит expand).
    final record = RecordModel.fromJson(userMap);
    pb.authStore.save(token, record);

    // Зеркалим в мок-AppController, чтобы остальные экраны жили как раньше.
    final user = AppUser(
      id: record.id,
      name: record.getStringValue('name'),
      phone: phone,
      rating: record.getDoubleValue('rating_as_customer'),
      reviewsCount: record.getIntValue('reviews_count_as_customer'),
    );
    _ref.read(appControllerProvider.notifier).completeAuthRemote(user);
    return true;
  }

  /// Logout — очистка PB-сессии и мок-стейта.
  Future<void> logout() async {
    _pb?.authStore.clear();
    _ref.read(appControllerProvider.notifier).logout();
  }

  /// Текущий PB-юзер (или null).
  RecordModel? get currentUser => _pb?.authStore.record;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(pocketbaseProvider), ref);
});
