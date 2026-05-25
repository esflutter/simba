import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/widgets/app_toast.dart';

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (context, _) => MaterialApp(home: child),
  );
}

/// Заглатывает 3-секундный auto-dismiss таймер тоста, чтобы тестовый
/// фреймворк не падал на pending timers по окончании теста.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  group('AppToast', () {
    testWidgets('показ тоста с текстом — текст виден на экране', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(_wrap(Builder(
        builder: (ctx) {
          capturedContext = ctx;
          return const Scaffold(body: SizedBox.shrink());
        },
      )));
      await tester.pumpAndSettle();

      AppToast.show(capturedContext, 'Тестовый текст');
      await tester.pump();
      expect(find.text('Тестовый текст'), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('два подряд тоста — на экране только последний', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(_wrap(Builder(
        builder: (ctx) {
          capturedContext = ctx;
          return const Scaffold(body: SizedBox.shrink());
        },
      )));
      await tester.pumpAndSettle();

      AppToast.show(capturedContext, 'Первый');
      await tester.pump();
      AppToast.show(capturedContext, 'Второй');
      await tester.pump();

      expect(find.text('Первый'), findsNothing);
      expect(find.text('Второй'), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('контекст без Overlay — не падает', (tester) async {
      late BuildContext rawContext;
      await tester.pumpWidget(Builder(builder: (ctx) {
        rawContext = ctx;
        return const SizedBox.shrink();
      }));
      expect(() => AppToast.show(rawContext, 'Без overlay'), returnsNormally);
    });

    testWidgets('success → плашка с этим текстом', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.shrink());
      })));
      await tester.pumpAndSettle();
      AppToast.success(ctx, 'OK');
      await tester.pump();
      expect(find.text('OK'), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('error → плашка с этим текстом', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_wrap(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.shrink());
      })));
      await tester.pumpAndSettle();
      AppToast.error(ctx, 'Ошибка');
      await tester.pump();
      expect(find.text('Ошибка'), findsOneWidget);
      await _drainToast(tester);
    });
  });
}
