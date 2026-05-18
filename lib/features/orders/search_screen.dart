import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/order_display.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/models/models.dart';
import '../../data/remote/orders_repository.dart';
import 'order_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  /// Кэш отфильтрованного результата для текущего запроса. Без него
  /// каждое нажатие клавиши прогоняло where+sort по всему списку даже
  /// при ребилдах, не связанных с _query (например, при переключении
  /// провайдеров). Ключ собран из identity-хэша источника и фильтрующих
  /// полей; при любом изменении пересчитываем, иначе отдаём прошлый.
  List<Order>? _cachedResults;
  int? _cachedKey;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      setState(() => _query = _ctrl.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _matches(Order o, String q) {
    if (q.isEmpty) return false;
    final lq = q.toLowerCase();
    return o.title.toLowerCase().contains(lq) ||
        o.address.toLowerCase().contains(lq) ||
        categoryNameOf(o).toLowerCase().contains(lq);
  }

  List<Order> _buildResults({
    required List<Order> source,
    required String? selectedCityId,
    required String? myId,
    required String query,
  }) {
    final key = Object.hash(
      identityHashCode(source),
      source.length,
      selectedCityId,
      myId,
      query,
    );
    if (_cachedKey == key && _cachedResults != null) return _cachedResults!;
    final filtered = source
        .where((o) =>
            o.status == OrderStatus.open &&
            !o.isExpiredOpen &&
            !o.isStaleOpenWithoutExecutor &&
            (selectedCityId == null ||
                o.cityId == null ||
                o.cityId == selectedCityId) &&
            (myId == null || o.customerId != myId) &&
            _matches(o, query))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cachedKey = key;
    _cachedResults = filtered;
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // .select — иначе каждое нажатие клавиши в поиске + любая мутация
    // AppState ребилдит экран целиком.
    final mockOrders = ref.watch(
      appControllerProvider.select((s) => s.orders),
    );
    final selectedCityId = ref.watch(
      appControllerProvider.select((s) => s.selectedCityId),
    );
    final myId = ref.watch(
      appControllerProvider.select((s) => s.user?.id),
    );
    // Источник — фид из PB (если есть), иначе мок-стейт.
    final remoteFeed = ref.watch(feedOrdersProvider).maybeWhen(
          data: (xs) => xs,
          orElse: () => null,
        );
    final source = remoteFeed ?? mockOrders;
    // Те же фильтры, что в ленте: open, не expired, не stale-30d, мой
    // город, не свой. Плюс совпадение поискового запроса. Кэшируем по
    // ключу (source, city, myId, query) — на каждое нажатие клавиши при
    // том же остальном контексте отдаём готовый результат.
    final results = _buildResults(
      source: source,
      selectedCityId: selectedCityId,
      myId: myId,
      query: _query,
    );
    final hasQuery = _query.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── White section: back button only ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44.h,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: const AppBackButton(),
                  ),
                ),
              ),
            ),
          ),
          // ── Gray section: search field ──
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: _SearchField(
              controller: _ctrl,
              focusNode: _focus,
            ),
          ),
          // ── Body ──
          Expanded(
            child: !hasQuery
                ? const SizedBox.shrink()
                : results.isEmpty
                    ? const _NoResults()
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => SizedBox(height: 16.h),
                        itemBuilder: (_, i) {
                          final o = results[i];
                          return OrderCard(
                            order: o,
                            categoryName: categoryNameOf(o),
                            onTap: () =>
                                context.push('/order/${o.id}?mode=feed'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(
            IconsaxPlusLinear.search_normal_1,
            size: 20.r,
            color: Colors.black.withValues(alpha: 0.60),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              cursorColor: AppColors.primary,
              textInputAction: TextInputAction.search,
              maxLength: 100,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w400,
                height: 1.29,
                letterSpacing: -0.43,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                counterText: '',
                hintText: 'Поиск',
                hintStyle: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.29,
                  letterSpacing: -0.43,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.search_normal_1,
              size: 80.r,
              color: AppColors.primary,
            ),
            SizedBox(height: 24.h),
            Text(
              'Нет результатов',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: -0.45,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Попробуйте найти что-нибудь еще',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.60),
                fontSize: 17.sp,
                fontWeight: FontWeight.w400,
                height: 1.29,
                letterSpacing: -0.40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
