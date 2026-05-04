import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import '../../data/mock/mock_data.dart';

class CityPickerScreen extends ConsumerStatefulWidget {
  const CityPickerScreen({super.key});

  @override
  ConsumerState<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends ConsumerState<CityPickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = MockData.cities
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    final canContinue = _selectedId != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppBackButton(),
              SizedBox(height: 16.h),
              Center(
                child: Container(
                  width: 56.w,
                  height: 56.r,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(IconsaxPlusLinear.location, color: AppColors.primary, size: 36.r),
                ),
              ),
              SizedBox(height: 16.h),
              Center(child: Text('Укажите город', style: AppText.h2())),
              SizedBox(height: 8.h),
              Text(
                'Покажем предложения и исполнителей в вашем городе',
                textAlign: TextAlign.center,
                style: AppText.body(color: AppColors.textSecondary),
              ),
              SizedBox(height: 24.h),
              AppTextField(
                label: 'Город или населённый пункт',
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: filtered.isEmpty
                    ? _NoCityFound(
                        onRequest: () => _showRequestSheet(context),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final selected = c.id == _selectedId;
                          return AppCard(
                            color: selected ? AppColors.primarySoft : AppColors.surface,
                            onTap: () => setState(() => _selectedId = c.id),
                            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
                            child: Row(
                              children: [
                                Expanded(child: Text(c.name, style: AppText.bodyLarge())),
                                if (selected)
                                  Icon(IconsaxPlusLinear.tick_circle,
                                      color: AppColors.primary, size: 22.r),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(height: 8.h),
              PrimaryButton(
                label: 'Далее',
                onPressed: canContinue
                    ? () {
                        ref.read(appControllerProvider.notifier).setCity(_selectedId!);
                        context.go('/auth/phone');
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (_) => const _RequestCitySheet(),
    );
  }
}

class _NoCityFound extends StatelessWidget {
  const _NoCityFound({required this.onRequest});
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.search_zoom_out,
                size: 48.r, color: AppColors.textTertiary),
            SizedBox(height: 16.h),
            Text(
              'Города пока нет в списке',
              style: AppText.h4(),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              'Оставьте заявку — добавим ваш населённый пункт',
              style: AppText.body(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            SecondaryButton(label: 'Оставить заявку', onPressed: onRequest),
          ],
        ),
      ),
    );
  }
}

class _RequestCitySheet extends StatefulWidget {
  const _RequestCitySheet();

  @override
  State<_RequestCitySheet> createState() => _RequestCitySheetState();
}

class _RequestCitySheetState extends State<_RequestCitySheet> {
  final _ctrl = TextEditingController();
  bool get _enabled => _ctrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16.w,
        16.h,
        16.w,
        MediaQuery.of(context).viewInsets.bottom + 16.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text('Заявка на добавление города', style: AppText.h4()),
          SizedBox(height: 16.h),
          AppTextField(
            label: 'Название города',
            controller: _ctrl,
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Отправить',
            onPressed: _enabled
                ? () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Заявка отправлена. Спасибо!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
