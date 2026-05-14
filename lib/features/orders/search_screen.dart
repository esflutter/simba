import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';
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

  String _categoryName(String id) => MockData.categories
      .firstWhere((c) => c.id == id, orElse: () => MockData.categories.last)
      .name;

  bool _matches(Order o, String q) {
    if (q.isEmpty) return false;
    final lq = q.toLowerCase();
    return o.title.toLowerCase().contains(lq) ||
        o.address.toLowerCase().contains(lq) ||
        _categoryName(o.categoryId).toLowerCase().contains(lq);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    // Источник — фид из PB (если есть), иначе мок-стейт.
    final remoteFeed = ref.watch(feedOrdersProvider).maybeWhen(
          data: (xs) => xs,
          orElse: () => null,
        );
    final source = remoteFeed ?? state.orders;
    // Те же фильтры, что в feed_screen: open, не expired, мой город, не мой
    // заказ. Плюс совпадение поискового запроса. Сортировка от новых к старым.
    final selectedCityId = state.selectedCityId;
    final myId = state.user?.id;
    final results = source
        .where((o) =>
            o.status == OrderStatus.open &&
            !o.isExpiredOpen &&
            (selectedCityId == null ||
                o.cityId == null ||
                o.cityId == selectedCityId) &&
            (myId == null || o.customerId != myId) &&
            _matches(o, _query))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
                            categoryName: _categoryName(o.categoryId),
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
                color: Colors.black,
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
                color: Colors.black,
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
