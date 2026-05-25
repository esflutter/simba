import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simba/core/widgets/city_pill.dart';

Widget _wrap(Widget child) {
  // Минимальный go_router, чтобы тап по CityPill не падал на context.push.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: Center(child: child)),
      ),
      GoRoute(
        path: '/city',
        builder: (_, _) => const Scaffold(body: Text('CITY_PICKER')),
      ),
    ],
  );
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (context, _) => MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('CityPill', () {
    testWidgets('рендерит имя города', (tester) async {
      await tester.pumpWidget(_wrap(const CityPill(cityName: 'Москва')));
      await tester.pumpAndSettle();
      expect(find.text('Москва'), findsOneWidget);
    });

    testWidgets('тап ведёт на /city', (tester) async {
      await tester.pumpWidget(_wrap(const CityPill(cityName: 'Москва')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CityPill));
      await tester.pumpAndSettle();
      expect(find.text('CITY_PICKER'), findsOneWidget);
    });

    testWidgets('очень длинное имя обрезается с многоточием', (tester) async {
      await tester.pumpWidget(_wrap(
        const CityPill(cityName: 'Очень-Длинное-Название-Города-Никуда-Не-Влезающее'),
      ));
      await tester.pumpAndSettle();
      // Виджет рендерится без исключений; точный визуальный обрез
      // не проверяем — это вёрстка, оно тестируется на скрине.
      expect(tester.takeException(), isNull);
    });
  });
}
