import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_client.dart';

/// Кастомные эндпоинты по пользователям, которых нет в стандартном
/// PB CRUD. Сейчас здесь только запрос телефона контрагента по заказу.
class UsersRepository {
  UsersRepository(this._pb);

  final PocketBase? _pb;

  bool get isLive => _pb != null;

  /// Получает телефон контрагента (заказчик ↔ исполнитель) по orderId.
  /// На сервере роут проверяет, что вызывающий — участник заказа и что
  /// статус позволяет контакт. Возвращает `{phone, is_third_party}` или
  /// `null` при отказе/ошибке. На моках всегда `null` — клиент берёт
  /// `user.phone` напрямую из мок-данных.
  Future<ContactPhone?> contactPhone({
    required String userId,
    required String orderId,
  }) async {
    final pb = _pb;
    if (pb == null) return null;
    Future<http.Response> doRequest() => http
        .post(
          Uri.parse('${pb.baseURL}/api/users/$userId/contact-phone'),
          headers: {
            if (pb.authStore.token.isNotEmpty)
              'Authorization': 'Bearer ${pb.authStore.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'order_id': orderId}),
        )
        .timeout(const Duration(seconds: 8));

    http.Response resp;
    try {
      resp = await doRequest();
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        // Один раз пробуем refresh + повторить запрос. Если refresh не
        // сработал — отдаём null, верхний уровень покажет «телефон скрыт».
        try {
          await pb
              .collection('users')
              .authRefresh()
              .timeout(const Duration(seconds: 10));
          resp = await doRequest();
        } catch (_) {
          return null;
        }
      }
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
    if (resp.statusCode != 200) return null;
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final phone = j['phone']?.toString();
      if (phone == null || phone.isEmpty) return null;
      return ContactPhone(
        phone: phone,
        isThirdParty: j['is_third_party'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class ContactPhone {
  const ContactPhone({required this.phone, required this.isThirdParty});
  final String phone;
  final bool isThirdParty;
}

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.read(pocketbaseProvider));
});

/// Аргументы для запроса телефона контрагента.
class ContactPhoneArgs {
  const ContactPhoneArgs({required this.userId, required this.orderId});
  final String userId;
  final String orderId;

  @override
  bool operator ==(Object other) =>
      other is ContactPhoneArgs &&
      other.userId == userId &&
      other.orderId == orderId;

  @override
  int get hashCode => Object.hash(userId, orderId);
}

/// Запрашивает телефон контрагента (исполнитель ↔ заказчик) для заданного
/// заказа через `POST /api/users/:userId/contact-phone`. Возвращает `null`
/// если PB не подключён (тогда экран показывает mock-phone).
///
/// `autoDispose` обязателен: без него кэш family-провайдера растёт
/// неограниченно — на каждую пару (userId, orderId) висит запись, пока
/// контейнер жив. autoDispose сбросит запись, когда последний слушатель
/// уйдёт с экрана.
final contactPhoneProvider = FutureProvider.autoDispose
    .family<String?, ContactPhoneArgs>((ref, args) async {
  final repo = ref.read(usersRepositoryProvider);
  if (!repo.isLive) return null;
  final res = await repo.contactPhone(
    userId: args.userId,
    orderId: args.orderId,
  );
  return res?.phone;
});
