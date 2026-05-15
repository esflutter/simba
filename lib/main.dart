import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/local/preferences_store.dart';
import 'data/remote/pocketbase_client.dart';

/// Единое описание стиля системных баров. Раньше тот же список параметров
/// был продублирован в `main()` (через `SystemChrome.setSystemUIOverlayStyle`)
/// и в `AnnotatedRegion` глобального билдера — любые изменения требовали
/// править оба места. Теперь источник один.
const _kSystemBarStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Color(0xFFF5F5F5),
  systemNavigationBarDividerColor: Color(0xFFF5F5F5),
  systemNavigationBarIconBrightness: Brightness.dark,
  // На Android 10+ ОС может рисовать полупрозрачный «контрастный» оверлей
  // поверх нижней панели — на цветных скринах это выглядит как синеватый
  // оттенок системных кнопок. Отключаем.
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(_kSystemBarStyle);
  final prefs = await SharedPreferences.getInstance();
  // PocketBase создаётся ОДИН раз здесь, чтобы привязать AsyncAuthStore к
  // тем же SharedPreferences и persist'ить токен между запусками.
  //
  // NB: authRefresh при бутстрапе НЕ дёргаем здесь — это делает
  // SplashScreen через authRepository.tryRefreshAuth (там же показывается
  // лоадер и обрабатывается результат). Иначе получали дубль запроса.
  final pb = buildPocketBase(prefs);

  runApp(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(PreferencesStore(prefs)),
        pocketbaseProvider.overrideWithValue(pb),
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
      // 360×800 — медианная logical-size современного Android (Pixel 6+/9
      // ≈ 360×808, Galaxy S22 ≈ 360×780). На iPhone 13 mini (375×812)
      // разница 4% — допустимая. См. memory `feedback_adaptive_layout`:
      // целевой эмулятор Pixel 9, вёрстка адаптивная.
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, child) {
        // Глобальный AnnotatedRegion удерживает стиль системных баров —
        // некоторые плагины/модалки/переходы могут его сбрасывать.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _kSystemBarStyle,
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
