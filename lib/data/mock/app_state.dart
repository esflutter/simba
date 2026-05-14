import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../local/preferences_store.dart';
import '../models/models.dart';
import '../remote/pocketbase_client.dart';
import 'mock_data.dart';

@immutable
class AppState {
  const AppState({
    required this.user,
    required this.role,
    required this.orders,
    required this.myOrders,
    required this.reviews,
    required this.selectedCityId,
    required this.executorActive,
    required this.searchRadiusKm,
    required this.onboardingSeen,
  });

  final AppUser? user;
  final UserRole role;
  final List<Order> orders;
  final List<Order> myOrders;
  final List<Review> reviews;
  final String? selectedCityId;
  final bool executorActive;
  final double searchRadiusKm;
  /// «Пользователь устройства уже видел онбординг». После первого
  /// прохождения остаётся true до полного wipe приложения — повторно
  /// онбординг не показывается даже после logout.
  final bool onboardingSeen;

  City get selectedCity => MockData.cities.firstWhere(
        (c) => c.id == selectedCityId,
        orElse: () => MockData.cities.first,
      );

  AppState copyWith({
    AppUser? user,
    UserRole? role,
    List<Order>? orders,
    List<Order>? myOrders,
    List<Review>? reviews,
    String? selectedCityId,
    bool? executorActive,
    double? searchRadiusKm,
    bool? onboardingSeen,
  }) =>
      AppState(
        user: user ?? this.user,
        role: role ?? this.role,
        orders: orders ?? this.orders,
        myOrders: myOrders ?? this.myOrders,
        reviews: reviews ?? this.reviews,
        selectedCityId: selectedCityId ?? this.selectedCityId,
        executorActive: executorActive ?? this.executorActive,
        searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      );
}

class AppController extends Notifier<AppState> {
  PreferencesStore? get _prefs {
    try {
      return ref.read(preferencesProvider);
    } catch (_) {
      return null; // тесты могут не подменять prefs — это допустимо
    }
  }

  @override
  AppState build() {
    final p = _prefs;
    final cityId = p?.cityId;
    final city = cityId == null
        ? MockData.cities.first
        : MockData.cities.firstWhere((c) => c.id == cityId,
            orElse: () => MockData.cities.first);
    return AppState(
      user: p?.user,
      role: p?.role ?? UserRole.customer,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(city.center),
      myOrders: Env.hasPocketbase
          ? const []
          : _withoutExpiredOpen(MockData.seedMyOrders(city.center)),
      reviews: Env.hasPocketbase ? const [] : MockData.seedReviews(),
      selectedCityId: cityId,
      executorActive: false,
      searchRadiusKm: 5,
      onboardingSeen: p?.onboardingSeen ?? false,
    );
  }

  /// Помечаем онбординг как пройденный. Флаг сохраняется в prefs пожизненно
  /// (на устройство), чтобы logout не возвращал юзера к экрану онбординга.
  /// Возвращает Future, чтобы вызывающий мог дождаться записи в prefs
  /// перед навигацией — иначе при быстром переходе на /city и cold restart
  /// прямо после онбординга флаг может не успеть сохраниться.
  Future<void> markOnboardingSeen() async {
    if (state.onboardingSeen) return;
    state = state.copyWith(onboardingSeen: true);
    final fut = _prefs?.setOnboardingSeen(true);
    if (fut != null) {
      try {
        await fut;
      } catch (_) {
        // Запись в prefs упала — state уже обновлён, на этом устройстве
        // в текущей сессии онбординг показываться не будет. На следующий
        // cold start, если ситуация повторится, юзер увидит онбординг
        // снова — терпимо.
      }
    }
  }

  /// Отбрасывает «размещённые» заказы, у которых истекла назначенная дата
  /// и так и не нашёлся исполнитель — они автоматически удаляются.
  List<Order> _withoutExpiredOpen(List<Order> orders) =>
      orders.where((o) => !o.isExpiredOpen).toList();

  void setCity(String id) {
    final c = MockData.cities.firstWhere((c) => c.id == id);
    state = state.copyWith(
      selectedCityId: id,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(c.center),
      myOrders: Env.hasPocketbase
          ? const []
          : _withoutExpiredOpen(MockData.seedMyOrders(c.center)),
    );
    _prefs?.setCityId(id);

    // Live-режим: PATCH users.city → источник правды на бэке. Fire-and-forget:
    // если PATCH не дойдёт (сеть/таймаут), при следующей авторизации
    // _consumeAuthEnvelope подтянет актуальный city с сервера, а до тех пор
    // юзер видит UX-соответствующий локальный selectedCityId. Не блокируем
    // переключатель города ожиданием HTTP — переключение должно быть instant.
    if (Env.hasPocketbase) {
      try {
        final pb = ref.read(pocketbaseProvider);
        if (pb != null &&
            pb.authStore.isValid &&
            pb.authStore.record != null) {
          pb
              .collection('users')
              .update(pb.authStore.record!.id, body: {'city': id})
              // ignore: body_might_complete_normally_catch_error
              .catchError((_) {
            // Молча — это background sync. Логирование оставим на бэке.
          });
        }
      } catch (_) {
        // ref.read may throw in tests without PB override — игнор.
      }
    }
  }

  void completeAuth({required String phone}) {
    final u = AppUser(
      id: 'me',
      name: '',
      phone: phone,
      rating: 0,
      reviewsCount: 0,
      cityId: state.selectedCityId,
    );
    state = state.copyWith(user: u);
    _prefs?.saveUser(u);
  }

  /// Принять авторизованного пользователя из PocketBase (после verify SMS).
  /// Сохраняем как локальный стейт — остальные экраны продолжают читать
  /// `state.user` без изменений.
  void completeAuthRemote(AppUser user) {
    state = state.copyWith(user: user);
    _prefs?.saveUser(user);
  }

  void completeProfile({
    required String name,
    String? photoPath,
    bool? hasTools,
    bool? hasTransport,
  }) {
    final u = state.user;
    if (u == null) return;
    final updated = u.copyWith(
      name: name.trim().isEmpty ? 'Пользователь' : name,
      photoPath: photoPath,
      hasTools: hasTools,
      hasTransport: hasTransport,
    );
    state = state.copyWith(user: updated);
    _prefs?.saveUser(updated);
  }

  void setRole(UserRole role) {
    state = state.copyWith(role: role);
    _prefs?.setRole(role);
  }

  void setExecutorActive(bool active) {
    state = state.copyWith(executorActive: active);
  }

  void setSearchRadius(double km) {
    state = state.copyWith(searchRadiusKm: km);
  }

  void createOrder(Order order) {
    state = state.copyWith(myOrders: [order, ...state.myOrders]);
  }

  void cancelOrder(String id) {
    // Удалить (= отменить «без следа») можно ТОЛЬКО размещённый заказ.
    // После того как заказчик принял исполнителя, заказ остаётся в системе
    // до завершения цикла FSM (markWorkDone → confirmPayment → completed)
    // или до автоматического закрытия по no-show через cron.
    final target = state.myOrders.where((o) => o.id == id).toList();
    if (target.isEmpty) return;
    if (target.first.status != OrderStatus.open) return;
    state = state.copyWith(
      myOrders: state.myOrders.where((o) => o.id != id).toList(),
    );
  }

  void acceptResponse(String orderId, String executorId) {
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) => o.id == orderId
              ? o.copyWith(
                  executorId: executorId,
                  status: OrderStatus.accepted,
                  responses: [executorId],
                )
              : o)
          .toList(),
    );
  }

  /// Отклонить отклик от конкретного пользователя — убрать его из responses.
  /// Заказ остаётся открытым, остальные отклики не трогаем.
  void declineResponse(String orderId, String userId) {
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) => o.id == orderId
              ? o.copyWith(
                  responses: o.responses.where((id) => id != userId).toList(),
                )
              : o)
          .toList(),
    );
  }

  /// Исполнитель ('me') откликается на open-заказ. Заказ остаётся в статусе
  /// open, в responses добавляется 'me'. Заказчик потом выбирает кого принять.
  void takeOrderAsExecutor(String orderId) {
    // Защита: нельзя откликаться на собственный заказ. На бэке это закрывает
    // фильтр /api/orders/feed (customer != me) + правило order_responses
    // createRule, но клиентскую защиту тоже держим — если бэк-фильтр сломается
    // или заказ окажется в state.orders по ошибке, мы не позволим отправить
    // запрос, который всё равно отвалится 403.
    final mine = state.myOrders.any((o) => o.id == orderId);
    if (mine) return;
    state = state.copyWith(
      orders: state.orders.map((o) {
        if (o.id != orderId) return o;
        if (o.responses.contains('me')) return o; // повторный отклик
        return o.copyWith(responses: [...o.responses, 'me']);
      }).toList(),
    );
  }

  void markWorkDone(String orderId, {required bool inMyOrders}) {
    if (inMyOrders) {
      state = state.copyWith(
        myOrders: state.myOrders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.awaitingPayment) : o)
            .toList(),
      );
    } else {
      state = state.copyWith(
        orders: state.orders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.awaitingPayment) : o)
            .toList(),
      );
    }
  }

  /// Сохранить отзыв «от меня» о другом участнике заказа.
  void addReview({
    required String orderId,
    required String toUserId,
    required int rating,
    required String comment,
    required List<String> tags,
  }) {
    final review = Review(
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
      fromUserId: 'me',
      toUserId: toUserId,
      orderId: orderId,
      rating: rating,
      comment: comment,
      tags: tags,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(reviews: [review, ...state.reviews]);
  }

  void confirmPayment(String orderId, {required bool inMyOrders}) {
    if (inMyOrders) {
      state = state.copyWith(
        myOrders: state.myOrders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.completed) : o)
            .toList(),
      );
    } else {
      state = state.copyWith(
        orders: state.orders
            .map((o) => o.id == orderId ? o.copyWith(status: OrderStatus.completed) : o)
            .toList(),
      );
    }
  }

  void logout() {
    // При logout сохраняем cityId и onboardingSeen — это устройство-локальные
    // флаги, не привязанные к юзеру. Логика «уже видел онбординг» и «выбрал
    // город» переживает logout, чтобы юзер на этом устройстве при следующем
    // входе сразу шёл на /auth/phone, без повторного онбординга и выбора.
    // Если при новом логине бэк пришлёт users.city — он перепишет локальный
    // (см. auth_repository._consumeAuthEnvelope).
    final keepCityId = state.selectedCityId;
    final city = state.selectedCity;
    state = AppState(
      user: null,
      role: UserRole.customer,
      orders: Env.hasPocketbase ? const [] : MockData.seedOrders(city.center),
      myOrders:
          Env.hasPocketbase ? const [] : MockData.seedMyOrders(city.center),
      reviews: Env.hasPocketbase ? const [] : MockData.seedReviews(),
      selectedCityId: keepCityId,
      executorActive: false,
      searchRadiusKm: state.searchRadiusKm,
      onboardingSeen: state.onboardingSeen,
    );
    _prefs?.clearUser();
    _prefs?.setRole(UserRole.customer);
  }
}

final appControllerProvider =
    NotifierProvider<AppController, AppState>(AppController.new);

AppUser userById(String id) {
  if (id == 'me') return MockData.demoCurrentUser;
  return MockData.otherUsers.firstWhere((u) => u.id == id, orElse: () => MockData.demoCurrentUser);
}

LatLng locationOf(City city) => city.center;
