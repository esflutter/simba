import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simba/features/create_order/order_summary_screen.dart';

Widget _wrap() {
  final router = GoRouter(
    initialLocation: '/create/summary',
    routes: [
      GoRoute(
        path: '/create/summary',
        builder: (_, _) => const OrderSummaryScreen(),
      ),
      GoRoute(
        path: '/home/:tab',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  return ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(360, 800),
      builder: (context, _) => MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  group('OrderSummaryScreen — smoke', () {
    testWidgets('экран рендерится без исключений на пустом черновике',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('виден заголовок «Создать заказ» / похожий', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // Какой-то заголовок страницы должен быть. Конкретный текст
      // может измениться при редизайне; ищем по подстроке.
      final hasHeader = find.textContaining('аказ').evaluate().isNotEmpty;
      expect(hasHeader, isTrue);
    });

    testWidgets('экран показывает поле способа оплаты в некоей форме',
        (tester) async {
      // На пустом черновике экран рендерит в т.ч. строку выбора оплаты.
      // На разных вариантах вёрстки лейбл может прокручиваться в нижний
      // секции — поэтому ищем не самое узкое условие («Укажите способ
      // оплаты»), а наличие любого упоминания слова «оплат».
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // Прокрутим список вниз, чтобы добраться до строки оплаты, если
      // она ниже видимой области.
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final hasPayment = find.textContaining('плат').evaluate().isNotEmpty;
      expect(hasPayment, isTrue);
    });
  });
}
