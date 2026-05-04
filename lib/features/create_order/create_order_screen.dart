import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/mock_data.dart';
import 'order_draft.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderDraftProvider);
    _titleCtrl = TextEditingController(text: d.title);
    _descCtrl = TextEditingController(text: d.description);
    _addressCtrl = TextEditingController(text: d.address);
    _phoneCtrl = TextEditingController(text: d.forOtherPhone ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final draft = ref.read(orderDraftProvider);
    if (draft.photoPaths.length >= 3) return;
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f != null) {
        ref.read(orderDraftProvider.notifier).update(
              photoPaths: [...draft.photoPaths, f.path],
            );
      }
    } catch (_) {}
  }

  void _removePhoto(int i) {
    final draft = ref.read(orderDraftProvider);
    final list = [...draft.photoPaths]..removeAt(i);
    ref.read(orderDraftProvider.notifier).update(photoPaths: list);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider);
    final canContinue = draft.categoryId != null &&
        _titleCtrl.text.trim().isNotEmpty &&
        _addressCtrl.text.trim().isNotEmpty;

    final categoryName = draft.categoryId == null
        ? 'Выберите категорию'
        : MockData.categories.firstWhere((c) => c.id == draft.categoryId).name;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: const AppBackButton(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text('Создать услугу', style: AppText.h1()),
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                children: [
                  _Pickable(
                    label: 'Категория работ',
                    value: categoryName,
                    isPlaceholder: draft.categoryId == null,
                    onTap: () => context.push('/create/category'),
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Название / Краткое описание работ',
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    onChanged: (v) {
                      ref.read(orderDraftProvider.notifier).update(title: v);
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Комментарий',
                    hint: 'Опишите, что конкретно нужно сделать',
                    controller: _descCtrl,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: (v) =>
                        ref.read(orderDraftProvider.notifier).update(description: v),
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Номер телефона заказчика',
                    hint: 'Если заказ для другого человека',
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onChanged: (v) => ref
                        .read(orderDraftProvider.notifier)
                        .update(forOtherPhone: v.isEmpty ? null : v, clearForOther: v.isEmpty),
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Адрес',
                    controller: _addressCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (v) {
                      ref.read(orderDraftProvider.notifier).update(address: v);
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 8.h),
                  _Pickable(
                    label: '',
                    value: 'Моё местоположение',
                    leading: Icon(IconsaxPlusLinear.gps, color: AppColors.primary, size: 22.r),
                    onTap: () async {
                      final result = await context.push('/create/address');
                      if (!mounted) return;
                      final updated = ref.read(orderDraftProvider).address;
                      if (updated.isNotEmpty) _addressCtrl.text = updated;
                      setState(() {});
                      // result not used; address comes from draft.
                      result; // suppress unused warning
                    },
                  ),
                  SizedBox(height: 12.h),
                  _PhotoRow(
                    photos: draft.photoPaths,
                    onAdd: _addPhoto,
                    onRemove: _removePhoto,
                  ),
                  SizedBox(height: 6.h),
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text(
                      'Не более 3 штук',
                      style: AppText.caption(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: PrimaryButton(
                label: 'Далее',
                onPressed: canContinue ? () => context.push('/create/summary') : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pickable extends StatelessWidget {
  const _Pickable({
    required this.label,
    required this.value,
    required this.onTap,
    this.isPlaceholder = false,
    this.leading,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isPlaceholder;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: 12.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label.isNotEmpty)
                      Text(label,
                          style: AppText.caption(color: AppColors.textSecondary)),
                    if (label.isNotEmpty) SizedBox(height: 2.h),
                    Text(
                      value,
                      style: AppText.bodyLarge(
                        color: isPlaceholder ? AppColors.textTertiary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 24.r),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.photos, required this.onAdd, required this.onRemove});
  final List<String> photos;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: onAdd,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(IconsaxPlusLinear.add, color: AppColors.primary, size: 22.r),
                SizedBox(width: 6.w),
                Text('Добавить фото',
                    style: AppText.body(color: AppColors.primary, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }
    final tiles = <Widget>[];
    if (photos.length < 3) {
      tiles.add(_AddTile(onTap: onAdd));
    }
    for (var i = 0; i < photos.length; i++) {
      tiles.add(_PhotoTile(path: photos[i], onRemove: () => onRemove(i)));
    }
    return SizedBox(
      height: 96.r,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => tiles[i],
        separatorBuilder: (_, _) => SizedBox(width: 8.w),
        itemCount: tiles.length,
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: SizedBox(
          width: 96.r,
          height: 96.r,
          child: Icon(IconsaxPlusLinear.add, size: 28.r, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96.r,
      height: 96.r,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: Image.file(File(path), width: 96.r, height: 96.r, fit: BoxFit.cover),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22.r,
                height: 22.r,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(IconsaxPlusLinear.close_circle, size: 14.r, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
