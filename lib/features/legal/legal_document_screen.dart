import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';

/// Какой документ показать. Тексты лежат локально в ассетах (assets/legal/*),
/// поэтому экран открывается без интернета и всегда доступен — это важно и для
/// проверки в сторах, и для пользователя в офлайне. На сервере те же документы
/// продолжают раздаваться статикой (для веб-ссылок) — при правке держать в
/// синхроне обе копии.
enum LegalDoc { privacy, terms }

extension _LegalDocMeta on LegalDoc {
  String get asset => switch (this) {
        LegalDoc.privacy => 'assets/legal/privacy.md',
        LegalDoc.terms => 'assets/legal/terms.md',
      };

  String get title => switch (this) {
        LegalDoc.privacy => 'Политика конфиденциальности',
        LegalDoc.terms => 'Пользовательское соглашение',
      };
}

/// Экран просмотра юридического документа. Рендерит ограниченный набор
/// markdown (заголовки, абзацы, списки, **жирный**, ссылки-подписи) — ровно
/// то, что есть в наших документах. Текст выделяемый, чтобы можно было
/// скопировать, например, адрес почты.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Row(
                  children: [
                    const AppBackButton(),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        doc.title,
                        style: AppText.body(weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: rootBundle.loadString(doc.asset),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                final text = snap.data;
                if (text == null || text.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.w),
                      child: Text(
                        'Не удалось загрузить документ',
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 40.h),
                  children: _buildBlocks(text),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Разбирает markdown построчно. Каждый абзац/пункт в исходнике — одна
  /// строка (так нам проще и надёжнее: строка = блок).
  List<Widget> _buildBlocks(String md) {
    final lines = md.replaceAll('\r\n', '\n').split('\n');
    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(SizedBox(height: 10.h));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(bottom: 4.h),
          child: Text(
            line.substring(2),
            style: AppText.bodyLarge(weight: FontWeight.w700)
                .copyWith(fontSize: 22.sp, height: 1.25),
          ),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: 18.h, bottom: 6.h),
          child: Text(
            line.substring(3),
            style: AppText.bodyLarge(weight: FontWeight.w600)
                .copyWith(fontSize: 17.sp),
          ),
        ));
        continue;
      }
      // Курсивная строка целиком (_..._) — подзаголовок «Редакция от …».
      if (line.length > 2 && line.startsWith('_') && line.endsWith('_')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Text(
            line.substring(1, line.length - 1),
            style: AppText.caption(color: AppColors.textSecondary),
          ),
        ));
        continue;
      }
      final base = AppText.body().copyWith(height: 1.5);
      if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: 4.h, bottom: 4.h, left: 4.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2.h, right: 8.w),
                child: Text('•', style: base),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(style: base, children: _inline(line.substring(2))),
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      widgets.add(Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: SelectableText.rich(
          TextSpan(style: base, children: _inline(line)),
        ),
      ));
    }
    return widgets;
  }

  /// Инлайн-разметка: **жирный** и [подпись](ссылка). Ссылку показываем
  /// цветом подписи (адрес почты остаётся выделяемым/копируемым), отдельной
  /// обработки тапа намеренно нет — это снимает возни с жизненным циклом
  /// recognizer'ов и зависимость от внешнего браузера.
  List<InlineSpan> _inline(String text) {
    final out = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        out.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      if (text.startsWith('**', i)) {
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          flush();
          out.add(TextSpan(
            text: text.substring(i + 2, end),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ));
          i = end + 2;
          continue;
        }
      }
      if (text[i] == '[') {
        final close = text.indexOf(']', i + 1);
        if (close != -1 && close + 1 < text.length && text[close + 1] == '(') {
          final paren = text.indexOf(')', close + 2);
          if (paren != -1) {
            flush();
            out.add(TextSpan(
              text: text.substring(i + 1, close),
              style: const TextStyle(color: AppColors.primary),
            ));
            i = paren + 1;
            continue;
          }
        }
      }
      buf.write(text[i]);
      i++;
    }
    flush();
    return out;
  }
}
