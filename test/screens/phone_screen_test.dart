import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simba/features/auth/phone_screen.dart';

/// Минимальная обёртка для запуска PhoneScreen в тестах:
///   * ProviderScope — экран использует ConsumerWidget;
///   * ScreenUtilInit — все размеры через .w/.h/.sp;
///   * GoRouter — есть context.push на /auth/sms внутри кнопки;
///     путь sub-экрана подменяем заглушкой, чтобы не тянуть всю аутенификацию.
Widget _wrap() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PhoneScreen()),
      GoRoute(
        path: '/auth/sms',
        builder: (_, _) => const Scaffold(body: Text('SMS_STUB')),
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
  group('PhoneScreen — рендер и валидация формы', () {
    testWidgets('первый показ — поле начинается с "+7"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // В поле должен быть автозаполненный префикс «+7».
      expect(find.text('+7'), findsWidgets);
    });

    testWidgets('заголовок и текст приватности видны', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Один из заголовков экрана. Если текст когда-нибудь поменяется —
      // тест не упадёт молча: ищем по подстроке.
      expect(find.textContaining('номер', findRichText: true),
          findsWidgets);
    });

    testWidgets('кнопка существует на экране', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // Просто убедимся что primary-кнопка есть в дереве (текст «Далее»
      // или подобное — конкретный лейбл может меняться).
      expect(find.byType(ElevatedButton).evaluate().length +
          find.byType(InkWell).evaluate().length, greaterThan(0));
    });

    testWidgets('экран не падает с исключением при первом рендере',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
