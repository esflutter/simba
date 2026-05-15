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
  });

  final String url;
  final BoxFit fit;
  final Widget? fallback;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ?? const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
