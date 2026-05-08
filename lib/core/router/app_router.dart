import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/role_picker_screen.dart';
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
import '../../features/orders/user_profile_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/support_screen.dart';
import '../../features/reviews/leave_review_screen.dart';
import '../../features/reviews/reviews_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => _buildRouter(ref));

/// Returns the next route to send a user to, depending on how complete their
/// onboarding is. Used both by Splash and by go_router's redirect.
String? nextOnboardingRoute(AppState state) {
  final user = state.user;
  if (user == null) return '/onboarding';
  if (state.selectedCityId == null) return '/city';
  if (user.name.trim().isEmpty) return '/auth/profile';
  return null;
}

GoRouter _buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: kDebugMode ? '/onboarding' : '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/city', builder: (_, _) => const CityPickerScreen()),
      GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(
        path: '/auth/sms',
        builder: (_, s) => SmsCodeScreen(phone: s.uri.queryParameters['phone'] ?? ''),
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
          GoRoute(
            path: 'review',
            builder: (_, s) => LeaveReviewScreen(orderId: s.pathParameters['id']!),
          ),
        ],
      ),
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
      return null;
    },
  );
}

extension AppRoles on UserRole {
  String get title => this == UserRole.customer ? 'Заказчик' : 'Исполнитель';
  String get cta => this == UserRole.customer ? 'Нужна помощь' : 'Готов помочь';
}
