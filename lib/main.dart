import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

/// Обработчик FCM-пушей, пришедших когда приложение в фоне или убито.
/// Должен быть top-level и помечен `@pragma('vm:entry-point')` — иначе
/// Flutter AOT (release-сборка) вырежет его, и пуш не доберётся до
/// изолята. Сам handler — лёгкий: систему уведомления Android и iOS
/// уже показали на лок-скрин/в шторке (FCM-payload с `notification` это
/// делает автоматически), нам остаётся инициализировать Firebase в
/// изоляте — на случай, если в дальнейшем добавим обработку `data`-only
/// сообщений (например, тихое обновление счётчика непрочитанных).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

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
  // Firebase — для FCM-пушей. Настройки берутся из google-services.json
  // (Android) и GoogleService-Info.plist (iOS), google-services Gradle
  // плагин/Firebase iOS-инициализатор сами подставляют параметры. Инициализация
  // обязательна ДО первого вызова Firebase API (FirebaseMessaging.instance).
  // Если в проекте файла нет — Firebase.initializeApp() кинет исключение;
  // приложение запустится, но пуши работать не будут.
  await Firebase.initializeApp();
  // Регистрируем background-handler — пуши, пришедшие когда приложение
  // в фоне/убито, обрабатываются в отдельном изоляте. Регистрация ДО
  // runApp обязательна, повторно через onMessage в SimbaApp foreground-
  // пуши тоже обрабатываются.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final prefs = await SharedPreferences.getInstance();
  // PreferencesStore.create — асинхронный конструктор: телефон лежит в
  // защищённом хранилище (Android Keystore / iOS Keychain), при старте
  // нужно его подтянуть в in-memory кэш и при необходимости мигрировать
  // со старого открытого ключа.
  final prefsStore = await PreferencesStore.create(prefs);
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
        preferencesProvider.overrideWithValue(prefsStore),
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
