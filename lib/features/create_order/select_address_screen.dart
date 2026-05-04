import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/mock/app_state.dart';
import 'order_draft.dart';

class SelectAddressScreen extends ConsumerStatefulWidget {
  const SelectAddressScreen({super.key});

  @override
  ConsumerState<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SelectAddressScreenState extends ConsumerState<SelectAddressScreen> {
  late LatLng _picked;
  late MapController _mapCtrl;
  late Future<Style> _styleFuture;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _picked = ref.read(orderDraftProvider).location ??
        ref.read(appControllerProvider).selectedCity.center;
    _styleFuture = StyleReader(
      uri: 'https://tiles.openfreemap.org/styles/positron',
    ).read();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Style>(
        future: _styleFuture,
        builder: (context, snap) {
          final mapBody = (snap.connectionState != ConnectionState.done)
              ? Container(
                  color: AppColors.surfaceVariant,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(color: AppColors.primary),
                )
              : snap.hasError
                  ? Container(
                      color: AppColors.surfaceVariant,
                      alignment: Alignment.center,
                      child: Text(
                        'Не удалось загрузить карту',
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapCtrl,
                      options: MapOptions(
                        initialCenter: _picked,
                        initialZoom: 13,
                        maxZoom: 18,
                        minZoom: 4,
                        onPositionChanged: (pos, _) =>
                            setState(() => _picked = pos.center),
                      ),
                      children: [
                        VectorTileLayer(
                          theme: snap.data!.theme,
                          sprites: snap.data!.sprites,
                          tileProviders: snap.data!.providers,
                        ),
                      ],
                    );

          return Stack(
            children: [
              mapBody,
              Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40.r),
                  child: Icon(Icons.location_on,
                      color: AppColors.markerRed, size: 48.r),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    child: Row(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const AppBackButton(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8.w,
                bottom: 96.h,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(3.r),
                  ),
                  child: Text(
                    '© OpenStreetMap © OpenMapTiles',
                    style: AppText.caption(color: AppColors.textTertiary).copyWith(
                      fontSize: 9.sp,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: PrimaryButton(
                      label: 'Выбрать здесь',
                      onPressed: () {
                        ref.read(orderDraftProvider.notifier).update(
                              location: _picked,
                              address:
                                  'Точка на карте (${_picked.latitude.toStringAsFixed(4)}, ${_picked.longitude.toStringAsFixed(4)})',
                            );
                        context.pop();
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
