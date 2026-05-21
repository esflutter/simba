import 'package:flutter/material.dart' show Brightness, Color, Colors;
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Единый билдер `SystemUiOverlayStyle` для всех экранов.
///
/// Раньше стиль системных баров был задан в трёх местах — `main.dart`
/// (глобальный default + `AnnotatedRegion` обёртки `MaterialApp`), на
/// сплеше и на онбординге. На сплеше и онбординге забыли проставить
/// `systemNavigationBarDividerColor` и оба `*ContrastEnforced`-флага
/// — на Android 10+ это выливалось в тонкую полупрозрачную полосу /
/// «контрастный» оттенок над навигационными кнопками. Здесь единая
/// фабрика, у которой меняется только цвет навигации и яркость иконок.
SystemUiOverlayStyle simbaSystemBarStyle({
  Color navBarColor = AppColors.background,
  Brightness navIconBrightness = Brightness.dark,
  Brightness statusIconBrightness = Brightness.dark,
}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: statusIconBrightness,
    statusBarBrightness: statusIconBrightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarColor: navBarColor,
    systemNavigationBarDividerColor: navBarColor,
    systemNavigationBarIconBrightness: navIconBrightness,
    // На Android 10+ ОС может рисовать полупрозрачный «контрастный»
    // оверлей поверх нижней панели — на цветных экранах это выглядит
    // как синеватый оттенок системных кнопок. Отключаем везде.
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}
