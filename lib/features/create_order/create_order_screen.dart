import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/utils/location_permission.dart';
import '../../core/utils/ru_phone_formatter.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/mock_data.dart';
import '../../data/remote/dadata_client.dart';
import 'order_draft.dart';
import 'select_address_screen.dart';
import 'select_category_screen.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key, this.forOther = false});
  final bool forOther;

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderDraftProvider);
    _titleCtrl = TextEditingController(text: d.title);
    _descCtrl = TextEditingController(text: d.description);
    _addressCtrl = TextEditingController(text: d.address);
    _phoneCtrl = TextEditingController(
      text: widget.forOther ? (d.forOtherPhone?.isNotEmpty == true ? d.forOtherPhone! : '+7') : '',
    );
    // Защита от удалённой/невалидной категории: если в драфте лежит
    // categoryId, которого больше нет в каталоге — сбрасываем,
    // иначе firstWhere ниже упадёт исключением при build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final draft = ref.read(orderDraftProvider);
      if (draft.categoryId != null &&
          !MockData.categories.any((c) => c.id == draft.categoryId)) {
        ref.read(orderDraftProvider.notifier).update(categoryId: null);
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// Потолок размера загружаемого фото (МБ). ImagePicker с maxWidth/Height 1920
  /// + imageQuality 80 обычно выдаёт 1-3 МБ; 8 МБ — запас для пограничных
  /// случаев (RAW с зеркалки, 4K с iPhone Pro). Бэк-схема orders.photos
  /// синхронизирована — maxSize=8 МБ.
  static const double _kMaxPhotoMb = 8.0;

  Future<void> _addPhoto() async {
    final draft = ref.read(orderDraftProvider);
    if (draft.photoPaths.length >= 3) return;
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (f == null) return;
      // 1) image_picker нативно пересжал. 2) Если всё равно >8 МБ
      // (большой PNG/HEIC/RAW из странной галереи) — дожимаем через
      // flutter_image_compress циклом quality 70→50→30→15.
      final ready = await ensurePhotoUnderLimit(f.path, _kMaxPhotoMb);
      if (!mounted) return;
      if (ready == null) {
        AppToast.show(context, 'Не удалось обработать фото. Попробуйте другое.');
        return;
      }
      ref.read(orderDraftProvider.notifier).update(
            photoPaths: [...draft.photoPaths, ready.path],
          );
    } catch (_) {}
  }

  void _removePhoto(int i) {
    final draft = ref.read(orderDraftProvider);
    final list = [...draft.photoPaths]..removeAt(i);
    ref.read(orderDraftProvider.notifier).update(photoPaths: list);
  }

  /// «Моё местоположение» через geolocator + reverse-geocode DaData.
  /// До этого экран выставлял центр города и текст «Моё местоположение»,
  /// что было неинформативно (исполнитель видел метку в центре города).
  Future<void> _useMyLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      // Проверяем системный сервис локации до запроса permission — иначе
      // на устройствах с выключенным GPS permission-диалог не имеет смысла.
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        AppToast.show(context, 'Включите геолокацию в настройках');
        return;
      }
      final ok = await ensureLocationPermission();
      if (!ok) {
        if (!mounted) return;
        AppToast.show(context, 'Разрешите доступ к геолокации');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final point = LatLng(pos.latitude, pos.longitude);
      final addr = await ref.read(dadataClientProvider).geolocate(point);
      if (!mounted) return;
      // Если reverse-geocode не сработал (нет PB или DaData офлайн) —
      // оставляем хотя бы координаты + дефолтную подпись.
      final addressString = (addr?.value.isNotEmpty == true)
          ? addr!.value
          : 'Точка на карте';
      ref.read(orderDraftProvider.notifier).update(
            address: addressString,
            location: point,
            addressFiasId: addr?.fiasId,
            addressKladrId: addr?.kladrId,
            cityFiasId: addr?.cityFiasId,
            postalCode: addr?.postalCode,
            qcGeo: addr?.qcGeo,
          );
      _addressCtrl.text = addressString;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Не удалось получить местоположение');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider);
    final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    // Принимаем только мобильные RU (79xxxxxxxxx); городские/8-800 — нет.
    final phoneOk = !widget.forOther ||
        (phoneDigits.length == 11 && phoneDigits.startsWith('79'));
    final canContinue = draft.categoryId != null &&
        _titleCtrl.text.trim().isNotEmpty &&
        _addressCtrl.text.trim().isNotEmpty &&
        phoneOk;

    // Защита от исчезнувшей категории при рендере: orElse → дефолт, но
    // отображаем placeholder. categoryId сбрасывается в initState через
    // postFrameCallback, чтобы не мутировать состояние во время build.
    final catMatch = draft.categoryId == null
        ? null
        : MockData.categories.firstWhere(
            (c) => c.id == draft.categoryId,
            orElse: () => MockData.categories.first,
          );
    final categoryKnown =
        catMatch != null && catMatch.id == draft.categoryId;
    final categoryName = !categoryKnown ? 'Выберите категорию' : catMatch.name;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    child: const AppBackButton(),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
                    child: Text(
                      'Создать заказ',
                      style: AppText.h1().copyWith(
                        height: 1.21,
                        letterSpacing: 0.40,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
                children: [
                  _Pickable(
                    label: 'Категория работ',
                    value: categoryName,
                    isPlaceholder: !categoryKnown,
                    height: 64.h,
                    onTap: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        useSafeArea: true,
                        builder: (_) => ClipRRect(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20.r)),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.92,
                            child: const SelectCategoryScreen(),
                          ),
                        ),
                      );
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 16.h),
                  AppTextField(
                    label: 'Название / Краткое описание работ',
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(50)],
                    onChanged: (v) {
                      ref.read(orderDraftProvider.notifier).update(title: v);
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    height: 132.h,
                    child: AppTextField(
                      label: 'Комментарий',
                      hint: 'Опишите, что конкретно нужно сделать',
                      controller: _descCtrl,
                      minLines: 3,
                      maxLines: 6,
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
                      onChanged: (v) =>
                          ref.read(orderDraftProvider.notifier).update(description: v),
                    ),
                  ),
                  if (widget.forOther) ...[
                    SizedBox(height: 16.h),
                    AppTextField(
                      label: 'Номер телефона заказчика',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [RuPhoneFormatter()],
                      onChanged: (v) {
                        ref
                            .read(orderDraftProvider.notifier)
                            .update(forOtherPhone: v.isEmpty ? null : v, clearForOther: v.isEmpty);
                        setState(() {});
                      },
                    ),
                  ],
                  SizedBox(height: 16.h),
                  _Pickable(
                    label: 'Адрес',
                    value: _addressCtrl.text,
                    onTap: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        useSafeArea: true,
                        builder: (_) => ClipRRect(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20.r)),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.92,
                            child: const SelectAddressScreen(),
                          ),
                        ),
                      );
                      if (!mounted) return;
                      final updated = ref.read(orderDraftProvider).address;
                      if (updated.isNotEmpty) _addressCtrl.text = updated;
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 6.h),
                  _Pickable(
                    label: '',
                    value: _isLocating
                        ? 'Определяем местоположение…'
                        : 'Моё местоположение',
                    leading: _isLocating
                        ? SizedBox(
                            width: 24.r,
                            height: 24.r,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(IconsaxPlusLinear.gps,
                            color: AppColors.primary, size: 24.r),
                    compact: true,
                    onTap: _isLocating ? () {} : _useMyLocation,
                  ),
                  SizedBox(height: 16.h),
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
                      style: AppText.caption(
                        color: Colors.black.withValues(alpha: 0.60),
                      ).copyWith(height: 1.67),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                child: PrimaryButton(
                  label: 'Далее',
                  onPressed: canContinue ? () => context.push('/create/summary') : null,
                ),
              ),
            ),
          ],
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
    this.compact = false,
    this.height,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isPlaceholder;
  final Widget? leading;
  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: compact ? Colors.transparent : AppColors.surface,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact ? 0 : (height ?? 56.h),
            maxHeight: height ?? double.infinity,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.w,
              vertical: compact ? 10.h : 4.h,
            ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: 16.w),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: AppText.caption(
                          color: Colors.black.withValues(alpha: 0.60),
                        ).copyWith(height: 1.33),
                      ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        color: isPlaceholder ? AppColors.textTertiary : AppColors.textPrimary,
                      ).copyWith(height: 1.50),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16.w),
              Icon(IconsaxPlusLinear.arrow_right_3, color: AppColors.primary, size: 24.r),
            ],
          ),
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
      return SizedBox(
        height: 50.h,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          child: InkWell(
            borderRadius: BorderRadius.circular(16.r),
            onTap: onAdd,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: AppColors.primary, size: 22.r),
                SizedBox(width: 3.w),
                Text(
                  'Добавить фото',
                  style: AppText.bodyLarge(color: AppColors.primary).copyWith(
                    height: 1.29,
                    letterSpacing: -0.43,
                  ),
                ),
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
      height: 72.r,
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
          width: 72.r,
          height: 72.r,
          child: Icon(Icons.add_rounded, size: 32.r, color: AppColors.primary),
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
      width: 72.r,
      height: 72.r,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: Image.file(File(path), width: 72.r, height: 72.r, fit: BoxFit.cover),
          ),
          Positioned(
            right: 4.r,
            top: 4.r,
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 16.r,
                height: 16.r,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(Icons.close_rounded, size: 12.r, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
