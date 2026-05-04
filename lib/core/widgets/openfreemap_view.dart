import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Маркер на OpenFreeMap карте. Цвет зависит от статуса заказа:
/// красный — открыт, оранжевый — есть отклики/принят, зелёный — завершён.
class OpenFreeMapMarker {
  const OpenFreeMapMarker({
    required this.id,
    required this.point,
    this.color = AppColors.markerRed,
  });

  final String id;
  final LatLng point;
  final Color color;
}

/// Карта на OpenFreeMap (бесплатные векторные тайлы OSM).
/// Атрибуция «© OpenStreetMap © OpenMapTiles» обязательна по лицензии.
class OpenFreeMapView extends StatefulWidget {
  const OpenFreeMapView({
    super.key,
    this.markers = const <OpenFreeMapMarker>[],
    this.initialCenter,
    this.initialZoom = 12,
    this.onMarkerTap,
    this.onMapTap,
    this.interactive = true,
    this.styleUri = 'https://tiles.openfreemap.org/styles/positron',
  });

  final List<OpenFreeMapMarker> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;
  final void Function(LatLng point)? onMapTap;
  final bool interactive;
  final String styleUri;

  @override
  State<OpenFreeMapView> createState() => _OpenFreeMapViewState();
}

class _OpenFreeMapViewState extends State<OpenFreeMapView> {
  late Future<Style> _styleFuture;

  @override
  void initState() {
    super.initState();
    _styleFuture = StyleReader(uri: widget.styleUri).read();
  }

  @override
  void didUpdateWidget(covariant OpenFreeMapView old) {
    super.didUpdateWidget(old);
    if (old.styleUri != widget.styleUri) {
      _styleFuture = StyleReader(uri: widget.styleUri).read();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Style>(
      future: _styleFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            child: SizedBox(
              width: 24.r,
              height: 24.r,
              child: const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            padding: EdgeInsets.all(16.w),
            child: Text(
              'Не удалось загрузить карту',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textSecondary),
            ),
          );
        }
        final style = snap.data!;
        final map = FlutterMap(
          options: MapOptions(
            initialCenter: widget.initialCenter ??
                style.center ??
                const LatLng(55.7558, 37.6173),
            initialZoom: widget.initialZoom,
            maxZoom: 18,
            minZoom: 4,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? (InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom)
                  : InteractiveFlag.none,
            ),
            onTap: widget.onMapTap == null
                ? null
                : (_, point) => widget.onMapTap!.call(point),
          ),
          children: [
            VectorTileLayer(
              theme: style.theme,
              sprites: style.sprites,
              tileProviders: style.providers,
            ),
            if (widget.markers.isNotEmpty)
              MarkerLayer(
                markers: widget.markers
                    .map(
                      (m) => Marker(
                        point: m.point,
                        width: 40.r,
                        height: 44.r,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onMarkerTap?.call(m.id),
                          child: Icon(
                            Icons.location_on,
                            color: m.color,
                            size: 36.r,
                            shadows: const [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );

        return Stack(
          children: [
            map,
            Positioned(
              right: 4.w,
              bottom: 4.h,
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
          ],
        );
      },
    );
  }
}
