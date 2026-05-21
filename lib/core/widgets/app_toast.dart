import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

/// Единый стиль всплывающих уведомлений: синяя плашка сверху экрана,
/// текст 13sp w400 #F5F5F5, padding 12/8, radius 8. Скрывается по тапу
/// на крестик или автоматически через [duration].
class AppToast {
  AppToast._();

  /// Показывает плашку поверх текущего экрана. Если уже показан другой
  /// тост — он скрывается, чтобы плашки не наслаивались.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _activeEntry?.remove();
    _activeTimer?.cancel();
    _activeEntry = null;
    _activeTimer = null;

    final overlay = Overlay.of(context);
    final controller = _ToastController();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppToastView(
        message: message,
        controller: controller,
        onDismiss: () {
          if (entry.mounted) entry.remove();
          if (_activeEntry == entry) {
            _activeEntry = null;
            _activeTimer?.cancel();
            _activeTimer = null;
          }
        },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);

    _activeTimer = Timer(duration, () {
      controller.dismiss?.call();
    });
  }
}

OverlayEntry? _activeEntry;
Timer? _activeTimer;

class _ToastController {
  VoidCallback? dismiss;
}

class _AppToastView extends StatefulWidget {
  const _AppToastView({
    required this.message,
    required this.controller,
    required this.onDismiss,
  });

  final String message;
  final _ToastController controller;
  final VoidCallback onDismiss;

  @override
  State<_AppToastView> createState() => _AppToastViewState();
}

class _AppToastViewState extends State<_AppToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    widget.controller.dismiss = _dismiss;
    _ac.forward();
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    try {
      await _ac.reverse();
    } catch (_) {
      // AnimationController может быть уже dispose'нут к этому моменту
      // (Overlay снят раньше, чем сработал авто-таймер). Без catch —
      // AssertionError в debug.
    }
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    // Снимаем ссылку из контроллера — иначе глобальный таймер на 3 секунды
    // продолжает держать `dismiss = _dismiss` и при срабатывании дёргает
    // метод уже dispose'нутого State'а. Симптом — AssertionError при
    // быстром переходе между экранами после показа тоста.
    if (identical(widget.controller.dismiss, _dismiss)) {
      widget.controller.dismiss = null;
    }
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      top: topInset + 52.h,
      left: 16.w,
      right: 16.w,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.background,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    height: 1.54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
