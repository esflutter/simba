import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simba/data/mock/app_state.dart';
import 'package:simba/features/city/city_picker_screen.dart';

Widget _wrap() {
  final router = GoRouter(
    initialLocation: '/city',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('ROOT'))),
      GoRoute(path: '/city', builder: (_, _) => const CityPickerScreen()),
      GoRoute(
        path: '/auth/phone',
        builder: (_, _) => const Scaffold(body: Text('PHONE')),
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
  group('CityPickerScreen — список и поиск', () {
    testWidgets('хотя бы один город-миллионник из списка отрисовался',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // Москва — гарантированно в списке миллионников.
      expect(find.text('Москва'), findsWidgets);
    });

    testWidgets('поиск по подстроке фильтрует список', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Тапаем по полю поиска и вводим «Каз».
      final searchField = find.byType(TextField);
      expect(searchField, findsAtLeastNWidgets(1));
      await tester.enterText(searchField.first, 'Каз');
      await tester.pumpAndSettle();

      // Казань должна быть в результатах.
      expect(find.text('Казань'), findsOneWidget);
      // А Москва — отфильтрована.
      expect(find.text('Москва'), findsNothing);
    });

    testWidgets('экран рендерится без исключений', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('тап по городу в режиме онбординга только подсвечивает выбор',
        (tester) async {
      // user==null → режим «новый юзер выбирает город перед регистрацией».
      // Тап по городу не должен вызывать setCity(...) и навигацию сразу —
      // юзер ещё должен подтвердить через «Далее».
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Раскроем поиск (в режиме онбординга он свёрнут).
      final searchField = find.byType(TextField);
      await tester.tap(searchField.first);
      await tester.pumpAndSettle();

      // Тапаем по Москве. Поскольку user==null, после тапа экран остаётся
      // открытым — текст «Москва» по-прежнему виден.
      await tester.tap(find.text('Москва').first);
      await tester.pumpAndSettle();

      expect(find.text('Москва'), findsWidgets);
      // Перехода на /auth/phone пока нет.
      expect(find.text('PHONE'), findsNothing);
    });
  });

  group('CityPickerScreen — после авторизации', () {
    testWidgets('user уже создан → тап по городу закрывает экран',
        (tester) async {
      // Подготавливаем ProviderContainer с залогиненным юзером.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appControllerProvider.notifier)
        ..setCity('msk')
        ..completeAuth(phone: '+79991234567');

      final router = GoRouter(
        // /city не имеет canPop=true; чтобы проверить что pop -> /home/my
        // через nextOnboardingRoute, добавим явный «корневой» экран до /city.
        initialLocation: '/home/my',
        routes: [
          GoRoute(
            path: '/home/:tab',
            builder: (_, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    // ignore: deprecated_member_use
                  },
                  child: const Text('HOME'),
                ),
              ),
            ),
          ),
          GoRoute(path: '/city', builder: (_, _) => const CityPickerScreen()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(360, 800),
            builder: (context, _) => MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Поскольку initial = /home/my, чтобы попасть на /city, дёрнем
      // непосредственно по роутингу. Используем context.go.
      final ctx = tester.element(find.text('HOME'));
      // ignore: use_build_context_synchronously
      GoRouter.of(ctx).push('/city');
      await tester.pumpAndSettle();

      // /city теперь сверху стека. Тапаем «Москва».
      await tester.tap(find.text('Москва').first);
      await tester.pumpAndSettle();

      // После выбора экран должен закрыться (pop) → вернёмся на /home/my.
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
