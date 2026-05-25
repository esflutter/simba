import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simba/data/models/models.dart';
import 'package:simba/features/orders/order_details_screen.dart'
    show orderByIdProvider;
import 'package:simba/features/reviews/leave_review_screen.dart';

Order _completedOrder() => Order(
      id: 'order_x',
      customerId: 'customer_y',
      categoryId: 'snow',
      title: 'Тестовый заказ',
      description: 'описание',
      address: 'Москва',
      location: const LatLng(55, 37),
      priceRub: 500,
      status: OrderStatus.completed,
      createdAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 2),
      executorId: 'executor_z',
    );

Widget _wrap({required String orderId}) {
  return ProviderScope(
    overrides: [
      orderByIdProvider(orderId).overrideWith((ref) async => _completedOrder()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(360, 800),
      builder: (context, _) => MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showLeaveReviewSheet(ctx, orderId),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Шторка отзыва раскладывается под мобильный экран и в тестовой среде
/// (по умолчанию 800×600) шире размера ScreenUtil 360×800 — RenderFlex
/// родительских Row выходит за границы. Это не баг продакшна, а артефакт
/// тестового канваса. Делаем виртуальный «телефон» 380×1400 на тест.
void _setMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(380, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('LeaveReviewSheet — smoke', () {
    testWidgets('открытие шторки показывает заголовок «Как вам заказ?»',
        (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(_wrap(orderId: 'order_x'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('Как вам заказ?'), findsOneWidget);
    });

    testWidgets('пять звёзд для рейтинга на шторке', (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(_wrap(orderId: 'order_x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      final stars = find.byType(Image).evaluate();
      expect(stars.length, greaterThanOrEqualTo(5));
    });

    testWidgets('тэги предлагаются в шторке', (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(_wrap(orderId: 'order_x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('Вежливый'), findsOneWidget);
    });

    testWidgets('крестик закрывает шторку', (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(_wrap(orderId: 'order_x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      final close = find.byIcon(Icons.close_rounded);
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text('Как вам заказ?'), findsNothing);
    });
  });
}
