import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/local/preferences_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFF5F5F5),
    systemNavigationBarDividerColor: Color(0xFFF5F5F5),
    systemNavigationBarIconBrightness: Brightness.dark,
    // На Android 10+ ОС может рисовать полупрозрачный «контрастный»
    // оверлей поверх нижней панели — на цветных скринах это выглядит
    // как синеватый оттенок системных кнопок. Отключаем.
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  ));
  final prefs = await SharedPreferences.getInstance();
  // В debug-режиме очищаем сохранённое состояние при каждом hot restart /
  // cold start, чтобы поток splash → онбординг прогонялся целиком.
  if (kDebugMode) {
    await prefs.clear();
  }
  runApp(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(PreferencesStore(prefs)),
      ],
      child: const SimbaApp(),
    ),
  );
}

class SimbaApp extends ConsumerWidget {
  const SimbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, child) {
        // Глобальный AnnotatedRegion удерживает стиль системных баров —
        // некоторые плагины/модалки/переходы могут его сбрасывать.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFFF5F5F5),
            systemNavigationBarDividerColor: Color(0xFFF5F5F5),
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarContrastEnforced: false,
            systemStatusBarContrastEnforced: false,
          ),
          child: MaterialApp.router(
            title: 'SimbA',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            routerConfig: ref.watch(routerProvider),
            locale: const Locale('ru', 'RU'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
          ),
        );
      },
    );
  }
}
