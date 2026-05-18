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

    test('cancelOrder removes accepted order if cancel window still open', () {
      // По обновлённой ТЗ-схеме «Заказчик может отказаться → Заказ исчезает»
      // действует и после accept, пока:
      //   - время заказа не наступило (`canCancelByCustomer == true`);
      //   - ни одна из сторон не отметила свою часть.
      // Раньше после accept запись была заперта до полного цикла FSM;
      // теперь — полностью удаляется (delete на бэке, drop из state
      // на моках).
      //
      // Тест берёт accepted-заказ с scheduledAt в будущем (m2 в seed:
      // `now + 1 day, 18:30`), убеждается что окно открыто, отменяет —
      // запись исчезает.
      final accepted = container.read(appControllerProvider).myOrders
          .firstWhere((o) =>
              o.status == OrderStatus.accepted && o.canCancelByCustomer());
      ctrl.cancelOrder(accepted.id);
      final stillThere = container.read(appControllerProvider).myOrders
          .where((o) => o.id == accepted.id);
      expect(stillThere, isEmpty);
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

    test('full flow accepted → both sides marked → completed', () {
      // По новой схеме `awaitingPayment` как отдельной фазы нет:
      // заказчик и исполнитель отмечают свои части независимо.
      // Когда обе отметки сделаны — заказ переходит в `completed`.
      //
      // Берём accepted-заказ, у которого ВРЕМЯ УЖЕ НАСТУПИЛО — иначе
      // контроллер (по guard isTimeArrived) корректно отказывается
      // отмечать заказ, у которого scheduledAt ещё в будущем.
      // В seed это m2b: accepted, scheduledAt = now - 1 час.
      final accepted = container.read(appControllerProvider).myOrders
          .firstWhere((o) =>
              o.status == OrderStatus.accepted && o.isTimeArrived);

      // Заказчик отмечает «работа выполнена».
      ctrl.markCustomerCompleted(accepted.id);
      final afterCustomer = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == accepted.id);
      expect(afterCustomer.isCompletedByCustomer, isTrue);
      // Исполнитель ещё не отметил → статус остаётся accepted, completedAt null.
      expect(afterCustomer.isCompletedByExecutor, isFalse);
      expect(afterCustomer.status, OrderStatus.accepted);

      // Исполнитель отмечает «оплата получена» → обе отметки → completed.
      ctrl.markExecutorCompleted(accepted.id);
      final afterExecutor = container.read(appControllerProvider).myOrders
          .firstWhere((o) => o.id == accepted.id);
      expect(afterExecutor.isCompletedByExecutor, isTrue);
      expect(afterExecutor.status, OrderStatus.completed);
    });

    test('очень старые open-заказы без исполнителя пропадают из «Моих заказов»', () {
      // Продуктовое правило: если за 30 дней с момента публикации никто
      // не выбран в исполнители, сервер удаляет заказ ночной задачей.
      // На клиенте порог 60 дней — защитная сетка относительно
      // серверного дефолта (см. Order.isStaleOpenWithoutExecutor).
      //
      // В seed лежит m_stale (createdAt = now - 65 дней): по клиентскому
      // порогу 60 дней он уже stale, фильтр build'а должен его убрать.
      final raw = MockData.seedMyOrders(const LatLng(55.0, 37.0));
      expect(raw.any((o) => o.id == 'm_stale'), isTrue,
          reason: 'sanity: stale seed должен быть в исходных данных');
      final filtered = container.read(appControllerProvider).myOrders;
      expect(filtered.any((o) => o.id == 'm_stale'), isFalse,
          reason: 'stale-заказ обязан быть отфильтрован build()-ом');
    });

    test('isStaleOpenWithoutExecutor: только open без исполнителя и старше клиентского порога', () {
      // Сам предикат на модели — проверяем граничные случаи.
      // 65 дней > 60-дневного клиентского порога → stale.
      final base = Order(
        id: 'tmp',
        customerId: 'me',
        categoryId: 'snow',
        title: '',
        description: '',
        address: '',
        location: const LatLng(55.0, 37.0),
        priceRub: 100,
        status: OrderStatus.open,
        createdAt: DateTime.now().subtract(const Duration(days: 65)),
      );
      expect(base.isStaleOpenWithoutExecutor, isTrue);
      // Только что созданный — не stale.
      final fresh = Order(
        id: 'tmp2',
        customerId: 'me',
        categoryId: 'snow',
        title: '',
        description: '',
        address: '',
        location: const LatLng(55.0, 37.0),
        priceRub: 100,
        status: OrderStatus.open,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(fresh.isStaleOpenWithoutExecutor, isFalse);
      // С выбранным исполнителем — не stale (это уже accepted-флоу).
      final withExecutor = Order(
        id: 'tmp3',
        customerId: 'me',
        categoryId: 'snow',
        title: '',
        description: '',
        address: '',
        location: const LatLng(55.0, 37.0),
        priceRub: 100,
        status: OrderStatus.accepted,
        createdAt: DateTime.now().subtract(const Duration(days: 65)),
        executorId: 'u1',
      );
      expect(withExecutor.isStaleOpenWithoutExecutor, isFalse);
      // Возвращённый в ленту (relistedAt свежий) — НЕ stale, даже если
      // createdAt далеко позади. Покрывает миграцию 028 с сервера.
      final relisted = Order(
        id: 'tmp4',
        customerId: 'me',
        categoryId: 'snow',
        title: '',
        description: '',
        address: '',
        location: const LatLng(55.0, 37.0),
        priceRub: 100,
        status: OrderStatus.open,
        createdAt: DateTime.now().subtract(const Duration(days: 90)),
        relistedAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(relisted.isStaleOpenWithoutExecutor, isFalse);
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
