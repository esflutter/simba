import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/pocketbase_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/primary_button.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/role_picker_screen.dart';
import '../../features/auth/sim_push_waiting_screen.dart';
import '../../features/auth/sms_code_screen.dart';
import '../../features/city/city_picker_screen.dart';
import '../../features/create_order/create_order_screen.dart';
import '../../features/create_order/order_summary_screen.dart';
import '../../features/create_order/select_address_screen.dart';
import '../../features/create_order/select_category_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/orders/order_details_screen.dart';
import '../../features/orders/responses_screen.dart';
import '../../features/orders/search_screen.dart';
import '../../features/orders/user_profile_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/support_screen.dart';
import '../../features/reviews/reviews_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => _buildRouter(ref));

/// Returns the next route to send a user to, depending on how complete their
/// onboarding is. Used both by Splash and by go_router's redirect.
///
/// Логика:
///   - Если онбординг ещё не показывали — `/onboarding`.
///   - Если онбординг был, но город не выбран — `/city`.
///   - Если город есть, но юзера нет — `/auth/phone` (логин).
///   - Если юзер есть, но имя пустое — `/auth/profile` (досборка профиля).
///   - Иначе `null` (= идём на главный).
///
/// Флаги `onboardingSeen` и `selectedCityId` хранятся в prefs и переживают
/// logout — повторный логин на этом устройстве сразу идёт на `/auth/phone`.
String? nextOnboardingRoute(AppState state) {
  if (!state.onboardingSeen) return '/onboarding';
  if (state.selectedCityId == null) return '/city';
  final user = state.user;
  if (user == null) return '/auth/phone';
  if (user.name.trim().isEmpty) return '/auth/profile';
  return null;
}

/// Куда направить юзера после успешной авторизации.
/// Новый юзер (только что зарегистрирован) → на profile-setup независимо от
/// прочего состояния — нужно собрать имя/город перед первым входом.
/// Существующий — по стандартному onboarding (city / home), который решит
/// `nextOnboardingRoute` исходя из заполненности профиля.
///
/// Используется обоими auth-экранами ([sms_code_screen], [sim_push_waiting_screen]),
/// чтобы логика "куда дальше" не дублировалась. Принимает [WidgetRef] —
/// тип ConsumerState/ConsumerWidget, под которым этот хелпер вызывается.
String postAuthRoute(WidgetRef ref, {required bool isNewUser}) {
  if (isNewUser) return '/auth/profile';
  final state = ref.read(appControllerProvider);
  return nextOnboardingRoute(state) ?? '/home/my';
}

GoRouter _buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/city', builder: (_, _) => const CityPickerScreen()),
      GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(
        path: '/auth/sms-waiting',
        builder: (_, s) => SimPushWaitingScreen(
          sessionId: s.uri.queryParameters['session_id'] ?? '',
          phone: s.uri.queryParameters['phone'] ?? '',
        ),
      ),
      GoRoute(
        path: '/auth/sms',
        builder: (_, s) => SmsCodeScreen(
          phone: s.uri.queryParameters['phone'] ?? '',
          sessionId: s.uri.queryParameters['session_id'],
        ),
      ),
      GoRoute(path: '/auth/profile', builder: (_, _) => const ProfileSetupScreen()),
      GoRoute(path: '/auth/role', builder: (_, _) => const RolePickerScreen()),
      GoRoute(
        path: '/home/:tab',
        builder: (_, s) => HomeShell(initialTab: s.pathParameters['tab'] ?? 'orders'),
      ),
      GoRoute(
        path: '/create',
        pageBuilder: (_, s) => NoTransitionPage(
          child: CreateOrderScreen(
            forOther: s.uri.queryParameters['for'] == 'other',
          ),
        ),
        routes: [
          GoRoute(path: 'category', builder: (_, _) => const SelectCategoryScreen()),
          GoRoute(path: 'address', builder: (_, _) => const SelectAddressScreen()),
          GoRoute(path: 'summary', builder: (_, _) => const OrderSummaryScreen()),
        ],
      ),
      GoRoute(
        path: '/order/:id',
        builder: (_, s) => OrderDetailsScreen(
          orderId: s.pathParameters['id']!,
          mode: (s.uri.queryParameters['mode'] ?? 'mine'),
        ),
        routes: [
          GoRoute(
            path: 'responses',
            builder: (_, s) => ResponsesScreen(orderId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'user/:userId',
            builder: (_, s) => UserProfileScreen(
              userId: s.pathParameters['userId']!,
              orderId: s.pathParameters['id'],
            ),
          ),
        ],
      ),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: '/profile/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/profile/reviews', builder: (_, _) => const ReviewsScreen()),
      GoRoute(path: '/profile/support', builder: (_, _) => const SupportScreen()),
    ],
    redirect: (context, st) {
      final loc = st.matchedLocation;
      final state = ref.read(appControllerProvider);
      final next = nextOnboardingRoute(state);
      const guarded = ['/home', '/create', '/order', '/profile/'];
      final isGuarded = guarded.any(loc.startsWith);
      if (isGuarded && next != null) return next;

      // Защита deep-link маршрутов авторизации. Иначе через intent/URL
      // можно открыть /auth/role или /auth/profile без авторизации и
      // перетереть role/имя в prefs до того, как юзер ввёл OTP.
      if (loc == '/auth/sms') {
        final phone = st.uri.queryParameters['phone'];
        if (phone == null || phone.isEmpty) return '/auth/phone';
      } else if (loc == '/auth/sms-waiting') {
        final sid = st.uri.queryParameters['session_id'];
        final phone = st.uri.queryParameters['phone'];
        if (sid == null || sid.isEmpty || phone == null || phone.isEmpty) {
          return '/auth/phone';
        }
      } else if (loc == '/auth/profile') {
        final pb = ref.read(pocketbaseProvider);
        final pbValid = pb != null && pb.authStore.isValid;
        if (!pbValid || state.user == null) return '/auth/phone';
        // Дополнительная защита от deep-link на /auth/profile минуя /city:
        // без выбранного города заполнение профиля бессмысленно (отклики и
        // создание заказов на бэке валидируют city, и заказчик упрётся в 403).
        if (state.selectedCityId == null || state.selectedCityId!.isEmpty) {
          return '/city';
        }
      } else if (loc == '/auth/role') {
        if (state.user == null) return '/auth/phone';
      }
      return null;
    },
    // Fallback для нераспознанных маршрутов (например, deeplink на /order/INVALID_ID
    // вне нашей схемы, или старые ссылки после рефакторинга). Показываем
    // дружелюбную «404» с кнопкой возврата вместо системного Flutter-screen.
    errorBuilder: (context, st) => _NotFoundPage(uri: st.uri.toString()),
  );
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.uri});
  final String uri;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w, 16.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(IconsaxPlusLinear.danger,
                  size: 80.r, color: AppColors.textTertiary),
              SizedBox(height: 16.h),
              Text(
                'Страница не найдена',
                style: AppText.h2().copyWith(letterSpacing: -0.10),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 9.h),
              Text(
                'Ссылка устарела или ведёт в недоступный раздел.',
                style: AppText.body().copyWith(
                  color: Colors.black.withValues(alpha: 0.60),
                  height: 1.38,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28.h),
              PrimaryButton(
                label: 'На главный экран',
                onPressed: () => context.go('/home/my'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension AppRoles on UserRole {
  String get title => this == UserRole.customer ? 'Заказчик' : 'Исполнитель';
  String get cta => this == UserRole.customer ? 'Не готов помочь' : 'Готов помочь';
}
