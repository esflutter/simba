import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onTap, this.color});

  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 44×44 — минимальный тач-таргет по Apple HIG / Material a11y. Иконку
    // оставляем 20.r как было; расширяется только чувствительная область
    // (SizedBox + InkResponse делают невидимый круг радиусом 22.r).
    return SizedBox(
      width: 44.r,
      height: 44.r,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ??
              () {
                // maybePop уважает PopScope: на экранах с несохранёнными
                // данными (ввод кода, редактирование профиля) он покажет
                // диалог подтверждения. Раньше тут был context.pop()
                // (go_router), который PopScope игнорировал — видимая
                // стрелка молча стирала введённый код / правки профиля.
                Navigator.of(context).maybePop();
              },
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20.r,
              color: color ?? AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
