import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_time_formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../data/remote/cities_repository.dart';

class OrderCard extends ConsumerWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.categoryName,
    required this.onTap,
    this.showTime = true,
    this.showCity = true,
  });

  final Order order;
  final String categoryName;
  final VoidCallback onTap;
  final bool showTime;

  /// Подставлять ли город к адресу. На каталоге («Заказы» и поиск по нему)
  /// все заказы одного города — там город не нужен (showCity: false).
  /// В остальных местах (мои заказы, история) город показываем.
  final bool showCity;

  String get _whenLabel {
    if (order.scheduledAt != null) {
      // toLocal(): scheduledAt в БД хранится в UTC, без перевода в локальное
      // время ночные заказы отображались на 1 день вперёд/назад.
      final dt = order.scheduledAt!.toLocal();
      // Если у заказа выставлено конкретное время (не 00:00), показываем
      // его в карточке — раньше в ленте была только дата, и исполнитель
      // узнавал «8 утра, не успею» только открыв детали.
      final hasTime = dt.hour != 0 || dt.minute != 0;
      final pattern = hasTime ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy';
      // Локаль 'ru_RU': без неё DateFormat подставляет английские месяцы,
      // и на узких экранах с 'dd MMMM' карточка вылазит. Тут — без месяца,
      // но единообразие со всеми остальными местами форматирования.
      return DateFormat(pattern, 'ru_RU').format(dt);
    }
    return order.asap ? 'Как можно быстрее' : 'Не указано';
  }

  String get _priceLabel => formatRub(order.priceRub);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Адрес с городом (кроме каталога). Если адрес пуст — оставляем пусто.
    final cityName = showCity ? ref.watch(cityNamesProvider)[order.cityId] : null;
    final addressLabel =
        (cityName != null && cityName.isNotEmpty && order.address.isNotEmpty)
            ? '$cityName, ${order.address}'
            : order.address;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CategoryChip(categoryName, dense: true),
                ),
              ),
              SizedBox(width: 8.w),
              // Стрелка-стрела из Figma (длинная линия + крупный уголок,
              // stroke-width около 2.5). Material `arrow_forward_rounded`
              // визуально тоньше и короче — пробовали, не совпадало.
              // Используем экспортированный webp напрямую.
              Image.asset(
                'assets/images/icon_arrow_forward.webp',
                width: 20.r,
                height: 20.r,
                color: AppColors.primary,
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            order.title,
            style: AppText.h3().copyWith(height: 1.20),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8.h),
          Text(
            addressLabel,
            style: AppText.bodySmall(
              color: Colors.black.withValues(alpha: 0.60),
            ).copyWith(height: 1.40),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: showTime
                    ? Text(
                        _whenLabel,
                        style: AppText.body(weight: FontWeight.w500)
                            .copyWith(height: 1.40),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(width: 8.w),
              Text(
                _priceLabel,
                style: AppText.body(
                  color: AppColors.primary,
                  weight: FontWeight.w600,
                ).copyWith(height: 1.40),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
