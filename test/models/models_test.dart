import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simba/data/models/models.dart';

void main() {
  group('PaymentMethodMapping', () {
    test('dbValue для cash', () {
      expect(PaymentMethod.cash.dbValue, 'cash');
    });

    test('dbValue для cashlessTransfer', () {
      expect(PaymentMethod.cashlessTransfer.dbValue, 'cashless_transfer');
    });

    test('label cash содержит «наличными»', () {
      expect(PaymentMethod.cash.label.toLowerCase(), contains('налич'));
    });

    test('label cashlessTransfer содержит «безналич»', () {
      expect(
          PaymentMethod.cashlessTransfer.label.toLowerCase(), contains('безналич'));
    });

    test('fromDbValue("cash") → cash', () {
      expect(PaymentMethodMapping.fromDbValue('cash'), PaymentMethod.cash);
    });

    test('fromDbValue("cashless_transfer") → cashlessTransfer', () {
      expect(PaymentMethodMapping.fromDbValue('cashless_transfer'),
          PaymentMethod.cashlessTransfer);
    });

    test('fromDbValue для неизвестного → fallback cash', () {
      expect(PaymentMethodMapping.fromDbValue('unknown_xyz'), PaymentMethod.cash);
    });

    test('fromDbValue для null → fallback cash без warning', () {
      expect(PaymentMethodMapping.fromDbValue(null), PaymentMethod.cash);
    });

    test('fromLabel инверсна dbValue', () {
      for (final m in PaymentMethod.values) {
        expect(PaymentMethodMapping.fromLabel(m.label), m);
      }
    });

    test('fromLabel для произвольной строки → fallback cash', () {
      expect(PaymentMethodMapping.fromLabel('какой-то текст'),
          PaymentMethod.cash);
    });
  });

  group('AppUser.ratingFor / reviewsCountFor', () {
    const user = AppUser(
      id: 'u',
      name: 'Тест',
      phone: '+79991234567',
      ratingAsCustomer: 4.2,
      reviewsCountAsCustomer: 12,
      ratingAsExecutor: 4.8,
      reviewsCountAsExecutor: 35,
    );

    test('рейтинг заказчика для роли customer', () {
      expect(user.ratingFor(UserRole.customer), 4.2);
      expect(user.reviewsCountFor(UserRole.customer), 12);
    });

    test('рейтинг исполнителя для роли executor', () {
      expect(user.ratingFor(UserRole.executor), 4.8);
      expect(user.reviewsCountFor(UserRole.executor), 35);
    });
  });

  group('AppUser.copyWith', () {
    const base = AppUser(
      id: 'u1',
      name: 'Иван',
      phone: '+79991234567',
      photoPath: '/path/to/avatar.jpg',
    );

    test('копирует с изменённым именем', () {
      final c = base.copyWith(name: 'Сергей');
      expect(c.name, 'Сергей');
      expect(c.phone, base.phone);
      expect(c.photoPath, base.photoPath);
    });

    test('явный null в photoPath очищает поле', () {
      final c = base.copyWith(photoPath: null);
      expect(c.photoPath, isNull);
    });

    test('без photoPath в copyWith — поле остаётся прежним', () {
      final c = base.copyWith(name: 'X');
      expect(c.photoPath, '/path/to/avatar.jpg');
    });
  });

  group('Order.copyWith', () {
    final base = Order(
      id: 'o1',
      customerId: 'me',
      categoryId: 'snow',
      title: 'Тест',
      description: 'описание',
      address: 'Москва',
      location: const LatLng(55, 37),
      priceRub: 500,
      status: OrderStatus.open,
      createdAt: DateTime(2026, 1, 1),
      executorId: 'u_exec',
      scheduledAt: DateTime(2026, 2, 1),
    );

    test('меняет status', () {
      final c = base.copyWith(status: OrderStatus.accepted);
      expect(c.status, OrderStatus.accepted);
      expect(c.executorId, base.executorId); // не затронуто
    });

    test('явный null в executorId сбрасывает исполнителя', () {
      final c = base.copyWith(executorId: null);
      expect(c.executorId, isNull);
    });

    test('без executorId в copyWith — поле сохраняется', () {
      final c = base.copyWith(status: OrderStatus.accepted);
      expect(c.executorId, 'u_exec');
    });

    test('явный null в scheduledAt сбрасывает дату', () {
      final c = base.copyWith(scheduledAt: null);
      expect(c.scheduledAt, isNull);
    });
  });

  group('reviewTagLabel', () {
    test('известный slug → русская подпись', () {
      expect(reviewTagLabel('polite'), 'Вежливый');
      expect(reviewTagLabel('reliable'), 'Надёжный');
    });

    test('неизвестный slug → возвращается как есть', () {
      expect(reviewTagLabel('quality'), 'quality');
      expect(reviewTagLabel('некий новый'), 'некий новый');
    });
  });

  group('OrderStatus enum', () {
    test('все значения имеют название', () {
      for (final s in OrderStatus.values) {
        expect(s.name.isNotEmpty, isTrue);
      }
    });

    test('содержит ключевые состояния', () {
      expect(OrderStatus.values, contains(OrderStatus.open));
      expect(OrderStatus.values, contains(OrderStatus.accepted));
      expect(OrderStatus.values, contains(OrderStatus.completed));
      expect(OrderStatus.values, contains(OrderStatus.cancelled));
    });
  });
}
