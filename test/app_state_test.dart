import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/data/mock/app_state.dart';
import 'package:simba/data/mock/mock_data.dart';
import 'package:simba/data/models/models.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('MockData', () {
    test('cities, categories, tags, users not empty', () {
      expect(MockData.cities.length, greaterThanOrEqualTo(15));
      expect(MockData.categories.length, equals(8));
      expect(MockData.reviewTags.length, greaterThan(0));
      expect(MockData.otherUsers.length, greaterThan(0));
    });

    test('seedOrders generates 5 open orders relative to city', () {
      final orders = MockData.seedOrders(const LatLng(55.0, 37.0));
      expect(orders.length, equals(5));
      expect(orders.every((o) => o.status == OrderStatus.open), isTrue);
      expect(orders.every((o) => o.customerId != 'me'), isTrue);
    });

    test('seedMyOrders includes one open + one accepted + one completed', () {
      final orders = MockData.seedMyOrders(const LatLng(55.0, 37.0));
      expect(orders.where((o) => o.status == OrderStatus.open).length, equals(1));
      expect(orders.where((o) => o.status == OrderStatus.accepted).length, equals(1));
      expect(orders.where((o) => o.status == OrderStatus.completed).length, equals(1));
      expect(orders.every((o) => o.customerId == 'me'), isTrue);
    });
  });

  group('AppController flow', () {
    late ProviderContainer container;
    late AppController ctrl;

    setUp(() {
      container = ProviderContainer();
      ctrl = container.read(appControllerProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('initial state has no user, default role customer', () {
      final s = container.read(appControllerProvider);
      expect(s.user, isNull);
      expect(s.role, UserRole.customer);
      expect(s.selectedCityId, isNull);
    });

    test('completeAuth creates user without rating', () {
      ctrl.completeAuth(phone: '+79001234567');
      final u = container.read(appControllerProvider).user!;
      expect(u.id, 'me');
      expect(u.phone, '+79001234567');
      expect(u.rating, 0);
      expect(u.reviewsCount, 0);
      expect(u.name, isEmpty);
    });

    test('completeProfile sets name without overriding rating', () {
      ctrl.completeAuth(phone: '+79001234567');
      ctrl.completeProfile(name: 'Тест Тестов');
      final u = container.read(appControllerProvider).user!;
      expect(u.name, 'Тест Тестов');
      expect(u.rating, 0);
    });

    test('takeOrderAsExecutor adds me to responses, status stays open', () {
      ctrl.setCity('msk');
      final firstOrderId = container.read(appControllerProvider).orders.first.id;
      ctrl.takeOrderAsExecutor(firstOrderId);
      final updated = container.read(appControllerProvider).orders
          .firstWhere((o) => o.id == firstOrderId);
      expect(updated.responses, contains('me'));
      expect(updated.status, OrderStatus.open);
      expect(updated.executorId, isNull);
    });

    test('takeOrderAsExecutor is idempotent', () {
      ctrl.setCity('msk');
      final orderId = container.read(appControllerProvider).orders.first.id;
      ctrl.takeOrderAsExecutor(orderId);
      ctrl.takeOrderAsExecutor(orderId);
      final updated = container.read(appControllerProvider).orders
          .firstWhere((o) => o.id == orderId);
      expect(updated.responses.where((r) => r == 'me').length, equals(1));
    });

    test('acceptResponse moves my order from open to accepted', () {
      final myOpen = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.open);
      ctrl.acceptResponse(myOpen.id, 'u1');
      final updated = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == myOpen.id);
      expect(updated.executorId, 'u1');
      expect(updated.status, OrderStatus.accepted);
    });

    test('cancelOrder marks my order cancelled', () {
      final myOpen = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.open);
      ctrl.cancelOrder(myOpen.id);
      final updated = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == myOpen.id);
      expect(updated.status, OrderStatus.cancelled);
    });

    test('full flow accepted → awaitingPayment → completed', () {
      final accepted = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.accepted);
      ctrl.markWorkDone(accepted.id, inMyOrders: true);
      expect(
        container.read(appControllerProvider).myOrders
            .firstWhere((o) => o.id == accepted.id).status,
        OrderStatus.awaitingPayment,
      );
      ctrl.confirmPayment(accepted.id, inMyOrders: true);
      expect(
        container.read(appControllerProvider).myOrders
            .firstWhere((o) => o.id == accepted.id).status,
        OrderStatus.completed,
      );
    });

    test('logout resets user and role but keeps city', () {
      ctrl.setCity('spb');
      ctrl.completeAuth(phone: '+79001234567');
      ctrl.setRole(UserRole.executor);
      ctrl.logout();
      final s = container.read(appControllerProvider);
      expect(s.user, isNull);
      expect(s.role, UserRole.customer);
      expect(s.selectedCityId, 'spb');
    });

    test('logout re-seeds feed/myOrders so prior session data does not leak', () {
      ctrl.setCity('msk');
      ctrl.completeAuth(phone: '+79001234567');
      // имитируем «грязное» состояние от прошлого пользователя:
      // принимаем отклик на свой заказ — myOrders мутирует.
      final myOpen = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.open);
      ctrl.acceptResponse(myOpen.id, 'u1');
      final dirty = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == myOpen.id);
      expect(dirty.executorId, 'u1');

      ctrl.logout();
      final freshOpen = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == myOpen.id, orElse: () => myOpen);
      // после logout фид должен быть пересеян из mock-генератора, без мутаций
      expect(freshOpen.executorId, isNull);
    });
  });

  group('MockData.generateOrderId', () {
    test('produces unique IDs across rapid calls', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(MockData.generateOrderId());
      }
      expect(ids.length, 1000);
    });

    test('always starts with m', () {
      for (var i = 0; i < 50; i++) {
        expect(MockData.generateOrderId().startsWith('m'), isTrue);
      }
    });
  });
}
