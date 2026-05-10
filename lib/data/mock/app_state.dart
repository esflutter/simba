import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../local/preferences_store.dart';
import '../models/models.dart';
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
  });

  final AppUser? user;
  final UserRole role;
  final List<Order> orders;
  final List<Order> myOrders;
  final List<Review> reviews;
  final String? selectedCityId;
  final bool executorActive;
  final double searchRadiusKm;

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
      orders: MockData.seedOrders(city.center),
      myOrders: MockData.seedMyOrders(city.center),
      reviews: MockData.seedReviews(),
      selectedCityId: cityId,
      executorActive: false,
      searchRadiusKm: 5,
    );
  }

  void setCity(String id) {
    final c = MockData.cities.firstWhere((c) => c.id == id);
    state = state.copyWith(
      selectedCityId: id,
      orders: MockData.seedOrders(c.center),
      myOrders: MockData.seedMyOrders(c.center),
    );
    _prefs?.setCityId(id);
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

  void completeProfile({
    required String name,
    String? photoPath,
    String? education,
    bool? hasTools,
    bool? hasTransport,
  }) {
    final u = state.user;
    if (u == null) return;
    final updated = u.copyWith(
      name: name.trim().isEmpty ? 'Пользователь' : name,
      photoPath: photoPath,
      education: education,
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
    state = state.copyWith(
      myOrders: state.myOrders
          .map((o) => o.id == id ? o.copyWith(status: OrderStatus.cancelled) : o)
          .toList(),
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
    // Заново пересеиваем фид по выбранному городу — иначе при перелогине
    // под другим телефоном остался бы фид прошлого пользователя.
    final city = state.selectedCity;
    state = AppState(
      user: null,
      role: UserRole.customer,
      orders: MockData.seedOrders(city.center),
      myOrders: MockData.seedMyOrders(city.center),
      reviews: MockData.seedReviews(),
      selectedCityId: state.selectedCityId,
      executorActive: false,
      searchRadiusKm: state.searchRadiusKm,
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
