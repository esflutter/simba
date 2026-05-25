import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/widgets/app_network_image.dart';

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AppNetworkImage', () {
    testWidgets('пустой url → показывает fallback', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppNetworkImage(
          url: '',
          fallback: Text('FALLBACK'),
          width: 48,
          height: 48,
        ),
      ));
      await tester.pump();
      expect(find.text('FALLBACK'), findsOneWidget);
    });

    testWidgets('пустой url без fallback — пустой контейнер заданного размера',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppNetworkImage(url: '', width: 48, height: 48),
      ));
      await tester.pump();
      // SizedBox со заданными размерами рендерится — ошибок нет.
      // (Сам fallback по умолчанию — SizedBox.shrink().)
      expect(tester.takeException(), isNull);
    });

    testWidgets('не пустой url не падает в build (загрузка идёт асинхронно)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AppNetworkImage(
          url: 'https://example.com/img.png',
          width: 48,
          height: 48,
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
