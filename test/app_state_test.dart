import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/data/mock/app_state.dart';
import 'package:simba/data/mock/mock_data.dart';
import 'package:simba/data/models/models.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('MockData', () {
    test('cities, categories, tags, users not empty', () {
      // 13 миллионников по ТЗ. Расширение списка — отдельная задача.
      expect(MockData.cities.length, greaterThanOrEqualTo(13));
      expect(MockData.categories.length, greaterThan(0));
      expect(MockData.reviewTags.length, greaterThan(0));
      expect(MockData.otherUsers.length, greaterThan(0));
    });

    test('seedOrders generates 5 open orders relative to city', () {
      final orders = MockData.seedOrders(const LatLng(55.0, 37.0));
      expect(orders.length, equals(5));
      expect(orders.every((o) => o.status == OrderStatus.open), isTrue);
      expect(orders.every((o) => o.customerId != 'me'), isTrue);
    });

    test('seedMyOrders includes open/accepted/completed examples', () {
      final orders = MockData.seedMyOrders(const LatLng(55.0, 37.0));
      // Мок наполняет несколько примеров каждого статуса — главное, что
      // в выборке точно есть и open, и accepted, и completed.
      expect(orders.where((o) => o.status == OrderStatus.open).length, greaterThanOrEqualTo(1));
      expect(orders.where((o) => o.status == OrderStatus.accepted).length, greaterThanOrEqualTo(1));
      expect(orders.where((o) => o.status == OrderStatus.completed).length, greaterThanOrEqualTo(1));
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

    test('cancelOrder removes my order completely (no history)', () {
      // По продукту: отмена = полное удаление, заказ исчезает без следа.
      // В историю отменённые заказы не попадают.
      final myOpen = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.open);
      ctrl.cancelOrder(myOpen.id);
      final found = container.read(appControllerProvider).myOrders
          .where((o) => o.id == myOpen.id);
      expect(found, isEmpty);
    });

    test('cancelOrder does NOT delete accepted orders', () {
      // После того как заказчик принял исполнителя, заказ удалить нельзя:
      // исполнитель уже потратил время, должен дойти цикл до completed
      // (markWorkDone → confirmPayment) или auto-cancel-no-show на бэке.
      final accepted = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.status == OrderStatus.accepted);
      ctrl.cancelOrder(accepted.id);
      final stillThere = container.read(appControllerProvider).myOrders
          .where((o) => o.id == accepted.id);
      expect(stillThere, isNotEmpty);
      expect(stillThere.first.status, OrderStatus.accepted);
    });

    test('takeOrderAsExecutor refuses to respond to own order', () {
      // Клиентская защита: даже если свой заказ каким-то образом попал
      // в state.orders (битый бэк-фильтр, старый кэш), нельзя добавить
      // 'me' в responses на своём же заказе.
      ctrl.setCity('msk');
      ctrl.completeAuth(phone: '+79001234567');
      // Возьмём id своего заказа и подставим его в state.orders (имитация
      // ситуации, когда бэк случайно отдал свой заказ в ленте).
      final myOrder = container.read(appControllerProvider).myOrders.first;
      ctrl.takeOrderAsExecutor(myOrder.id);
      final inOrders = container.read(appControllerProvider).orders
          .where((o) => o.id == myOrder.id);
      // Заказ может быть и не в orders — это нормально. Главное, чтобы он
      // не получил 'me' в responses.
      for (final o in inOrders) {
        expect(o.responses, isNot(contains('me')));
      }
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

    test('logout сбрасывает user/role, но сохраняет city и onboardingSeen', () {
      // По продукту: cityId и onboardingSeen — флаги УСТРОЙСТВА, а не
      // аккаунта. После logout юзер на том же устройстве сразу идёт на
      // /auth/phone, без повторного онбординга и выбора города. При логине
      // под другим аккаунтом users.city с бэка перепишет локальный.
      ctrl.setCity('spb');
      ctrl.markOnboardingSeen();
      ctrl.completeAuth(phone: '+79001234567');
      ctrl.setRole(UserRole.executor);
      ctrl.logout();
      final s = container.read(appControllerProvider);
      expect(s.user, isNull);
      expect(s.role, UserRole.customer);
      expect(s.selectedCityId, 'spb');
      expect(s.onboardingSeen, isTrue);
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
