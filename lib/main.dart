import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/system_bar_style.dart';
import 'data/local/preferences_store.dart';
import 'data/remote/pocketbase_client.dart';

/// Дефолтный стиль системных баров — для основного потока экранов.
/// Splash и онбординг используют тот же `simbaSystemBarStyle`, но с
/// другими цветами фона.
final _kSystemBarStyle = simbaSystemBarStyle();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Edge-to-edge: на Android 15+ (API 35+) свойства типа
  // `systemNavigationBarColor` игнорируются. Без edge-to-edge система
  // показывает дефолтный чёрный фон под кнопками навигации, даже если
  // приложение синее — на онбординге получалась видимая чёрная полоса
  // над кнопками. С edge-to-edge `Scaffold.backgroundColor` сам красит
  // эту область своим цветом, а SafeArea внутри даёт корректные отступы
  // для контента.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_kSystemBarStyle);
  // Подгружаем локализованные данные для пакета `intl` (русские месяцы
  // и дни недели). Без этого DateFormat с локалью 'ru_RU' падает с
  // LocaleDataException при первом форматировании — экран истории и
  // карточка заказа используют 'd MMMM yyyy' / 'dd.MM.yyyy HH:mm'.
  await initializeDateFormatting('ru_RU');
  final prefs = await SharedPreferences.getInstance();
  // PocketBase создаётся ОДИН раз здесь. Токен сессии хранится в
  // защищённом системном хранилище (Android Keystore / iOS Keychain),
  // не в обычных SharedPreferences — иначе на рутованном устройстве
  // он читается тривиально.
  //
  // NB: authRefresh при бутстрапе НЕ дёргаем здесь — это делает
  // SplashScreen через authRepository.tryRefreshAuth (там же показывается
  // лоадер и обрабатывается результат). Иначе получали дубль запроса.
  final pb = await buildPocketBase(prefs);

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
