import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simba/features/legal/legal_document_screen.dart';

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (context, _) => MaterialApp(home: child),
  );
}

void main() {
  group('LegalDocumentScreen', () {
    testWidgets('политика: ассет грузится и markdown рендерится без ошибок',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const LegalDocumentScreen(doc: LegalDoc.privacy)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Заголовок в шапке.
      expect(find.text('Политика конфиденциальности'), findsWidgets);
      // H1 из самого ассета (значит, строка загрузилась и `# ` распарсился).
      expect(
        find.text('Политика конфиденциальности приложения SimbA'),
        findsOneWidget,
      );
    });

    testWidgets('соглашение: ассет грузится и markdown рендерится без ошибок',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const LegalDocumentScreen(doc: LegalDoc.terms)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Пользовательское соглашение'), findsWidgets);
      expect(
        find.text('Пользовательское соглашение приложения SimbA'),
        findsOneWidget,
      );
    });
  });
}
