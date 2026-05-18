import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Единая обёртка над `CachedNetworkImage` для всего приложения.
///
/// До этого `Image.network` использовалась напрямую в аватарках авторов
/// отзывов, фото заказов и публичных профилях — без кэша. На экране
/// «Отзывы» из 50 карточек это давало 50 HTTP-запросов на каждое открытие.
///
/// Теперь любая удалённая картинка ходит через `CachedNetworkImage`:
/// дисковый + memory кэш + единый fallback-плейсхолдер.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallback,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final BoxFit fit;

  /// Виджет для случая, когда картинка не загрузилась или url пустой.
  /// Используется ТОЛЬКО как errorWidget; во время загрузки показывается
  /// прозрачный контейнер размером с виджет — чтобы не было «мигания»
  /// силуэтом аватара до подгрузки. Раньше placeholder тоже был
  /// fallback'ом, и юзер на доли секунды видел силуэт пустой аватарки.
  final Widget? fallback;
  final double? width;
  final double? height;

  /// Целевые габариты декодированного bitmap (px, не lp). Если не переданы,
  /// высчитываются из `width/height × devicePixelRatio` (capped до 512px) —
  /// крупный JPEG аватара (1024×1024) больше НЕ декодируется в полное
  /// разрешение под виджет 32×32lp. Раньше профильный экран с 20+ отзывами
  /// держал в RAM ~80МБ декодированных аватарок; теперь — порядка единиц МБ.
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    int? capDim(double? lp, int? explicit) {
      if (explicit != null) return explicit;
      if (lp == null) return null;
      final px = (lp * dpr).round();
      // 512px-cap: даже на 3×-устройствах 170lp = 510px, чего хватает для
      // любого «декоративного» аватара/тамбнейла. Выше — пусть декодит
      // нативное разрешение (например full-screen фото в order_details).
      if (px <= 0) return 1;
      return px > 512 ? 512 : px;
    }
    final errorView = fallback ?? const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: capDim(width, memCacheWidth),
      memCacheHeight: capDim(height, memCacheHeight),
      // Загрузка: прозрачный SizedBox размером с виджет. Силуэт-fallback
      // показывается только при ошибке/пустом url. Иначе на доли секунды
      // юзер видит «дефолтный» силуэт до подгрузки своей аватарки —
      // выглядит как глитч.
      placeholder: (_, _) => SizedBox(width: width, height: height),
      // Лёгкий fade-in без агрессивной плейсхолдер-анимации: 150мс
      // делает появление картинки плавным, но не «прыгающим».
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: Duration.zero,
      errorWidget: (_, _, _) => errorView,
    );
  }
}
