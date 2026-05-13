import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum UserRole { customer, executor }

enum OrderStatus {
  open,
  accepted,
  awaitingPayment,
  completed,
  cancelled,
}

enum PaymentMethod { cash }

@immutable
class City {
  const City({
    required this.id,
    required this.name,
    required this.center,
    this.dadataFiasId,
    this.boundsRadiusKm = 50.0,
  });

  final String id;
  final String name;
  final LatLng center;

  /// FIAS-идентификатор города (Federal Information Address System).
  /// Передаётся в DaData как `city_fias_id` для строгого ограничения
  /// поиска адресов рамками выбранного города. См. `select_address_screen`.
  /// Null означает «город без бэк-привязки» (моки без FIAS).
  final String? dadataFiasId;

  /// Радиус (км) от [center], внутри которого считается «город» для
  /// первого, дешёвого этапа валидации адреса (Phase 1 при тапе на карте).
  /// Точная проверка делается через DaData reverse-geocode (Phase 2)
  /// — сравнение `city_fias_id` из ответа DaData с [dadataFiasId].
  /// 50 км — разумный дефолт для миллионников РФ; для Москвы можно
  /// поставить 60 (агломерация), для Воронежа — 40 (компактный).
  final double boundsRadiusKm;
}

@immutable
class Category {
  const Category({required this.id, required this.name, required this.icon});
  final String id;
  final String name;
  final String icon;
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.photoPath,
    this.rating = 0.0,
    this.reviewsCount = 0,
    this.ratingAsCustomer = 0.0,
    this.reviewsCountAsCustomer = 0,
    this.ratingAsExecutor = 0.0,
    this.reviewsCountAsExecutor = 0,
    this.cityId,
    this.hasTools = false,
    this.hasTransport = false,
  });

  final String id;
  final String name;
  final String phone;
  final String? photoPath;

  /// Legacy-поле. В маркетплейсе основная роль — исполнитель, поэтому при
  /// маппинге из PB сюда кладётся [ratingAsExecutor]. UI, выбирающий рейтинг
  /// по текущей роли пользователя, должен читать [ratingAsCustomer] /
  /// [ratingAsExecutor] напрямую.
  final double rating;

  /// Legacy-поле — соответствует [reviewsCountAsExecutor] (см. [rating]).
  final int reviewsCount;

  /// Рейтинг пользователя как заказчика (агрегируется триггерами PB).
  final double ratingAsCustomer;
  final int reviewsCountAsCustomer;

  /// Рейтинг пользователя как исполнителя — основной для маркетплейса.
  final double ratingAsExecutor;
  final int reviewsCountAsExecutor;

  final String? cityId;
  final bool hasTools;
  final bool hasTransport;

  /// Возвращает рейтинг для конкретной роли. Используется на экранах,
  /// где видна роль контрагента (карточка отклика, профиль).
  double ratingFor(UserRole role) => role == UserRole.customer
      ? ratingAsCustomer
      : ratingAsExecutor;

  int reviewsCountFor(UserRole role) => role == UserRole.customer
      ? reviewsCountAsCustomer
      : reviewsCountAsExecutor;

  AppUser copyWith({
    String? name,
    String? phone,
    Object? photoPath = _sentinel,
    double? rating,
    int? reviewsCount,
    double? ratingAsCustomer,
    int? reviewsCountAsCustomer,
    double? ratingAsExecutor,
    int? reviewsCountAsExecutor,
    String? cityId,
    bool? hasTools,
    bool? hasTransport,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      // photoPath: явный `null` очищает фото, sentinel — оставляет как было.
      photoPath: identical(photoPath, _sentinel)
          ? this.photoPath
          : photoPath as String?,
      rating: rating ?? this.rating,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      ratingAsCustomer: ratingAsCustomer ?? this.ratingAsCustomer,
      reviewsCountAsCustomer:
          reviewsCountAsCustomer ?? this.reviewsCountAsCustomer,
      ratingAsExecutor: ratingAsExecutor ?? this.ratingAsExecutor,
      reviewsCountAsExecutor:
          reviewsCountAsExecutor ?? this.reviewsCountAsExecutor,
      cityId: cityId ?? this.cityId,
      hasTools: hasTools ?? this.hasTools,
      hasTransport: hasTransport ?? this.hasTransport,
    );
  }
}

const _sentinel = Object();

@immutable
class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.address,
    required this.location,
    required this.priceRub,
    required this.status,
    required this.createdAt,
    this.scheduledAt,
    this.asap = true,
    this.executorId,
    this.photoPaths = const [],
    this.responses = const [],
    this.paymentMethod = PaymentMethod.cash,
    this.forOtherPhone,
    this.customerName,
    this.customerPhotoUrl,
    this.executorName,
    this.executorPhotoUrl,
    this.categoryName,
    this.completedAt,
    this.workDoneAt,
    this.workConfirmedAt,
    this.paymentReceivedAt,
    this.cityId,
  });

  final String id;
  final String customerId;
  final String categoryId;
  final String title;
  final String description;
  final String address;
  final LatLng location;
  final int priceRub;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final bool asap;
  final String? executorId;
  final List<String> photoPaths;
  final List<String> responses;
  final PaymentMethod paymentMethod;
  final String? forOtherPhone;

  /// Поля, материализованные из `record.expand` при чтении из PocketBase.
  /// На моках всегда null — UI продолжает резолвить имена через локальные
  /// справочники (userById / MockData.categories).
  final String? customerName;
  final String? customerPhotoUrl;
  final String? executorName;
  final String? executorPhotoUrl;
  final String? categoryName;

  /// Дата перевода в status=completed. Источник правды для 30-дневного окна
  /// отзывов (см. `leave_review_screen`). На моках всегда null — там окно
  /// считается от scheduledAt / createdAt как best-effort fallback.
  final DateTime? completedAt;

  /// 3-step FSM-вехи. Все три заполнены ⇒ заказ автоматически переходит в
  /// completed (см. backend `onRecordUpdate("orders")`).
  final DateTime? workDoneAt;
  final DateTime? workConfirmedAt;
  final DateTime? paymentReceivedAt;

  /// ID города, в котором создан заказ (relation на coll. `cities`). Заказ
  /// привязывается к городу при создании и НЕ меняется — это immutable
  /// фильтр для ленты исполнителей. Заказчик может переключить свой
  /// `selectedCityId`, но старые заказы остаются в своём городе.
  final String? cityId;

  Order copyWith({
    OrderStatus? status,
    String? executorId,
    List<String>? responses,
    DateTime? scheduledAt,
    int? priceRub,
    DateTime? completedAt,
    DateTime? workDoneAt,
    DateTime? workConfirmedAt,
    DateTime? paymentReceivedAt,
    String? cityId,
  }) =>
      Order(
        id: id,
        customerId: customerId,
        categoryId: categoryId,
        title: title,
        description: description,
        address: address,
        location: location,
        priceRub: priceRub ?? this.priceRub,
        status: status ?? this.status,
        createdAt: createdAt,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        asap: asap,
        executorId: executorId ?? this.executorId,
        photoPaths: photoPaths,
        responses: responses ?? this.responses,
        paymentMethod: paymentMethod,
        forOtherPhone: forOtherPhone,
        customerName: customerName,
        customerPhotoUrl: customerPhotoUrl,
        executorName: executorName,
        executorPhotoUrl: executorPhotoUrl,
        categoryName: categoryName,
        completedAt: completedAt ?? this.completedAt,
        workDoneAt: workDoneAt ?? this.workDoneAt,
        workConfirmedAt: workConfirmedAt ?? this.workConfirmedAt,
        paymentReceivedAt: paymentReceivedAt ?? this.paymentReceivedAt,
        cityId: cityId ?? this.cityId,
      );
}

@immutable
class Review {
  const Review({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.orderId,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.createdAt,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String orderId;
  final int rating;
  final String comment;
  final List<String> tags;
  final DateTime createdAt;
}

extension OrderLifecycle on Order {
  /// Заказ относится к истории: завершён, отменён, либо запланированная
  /// дата начала уже прошла (наступило указанное время и позже).
  bool get isHistorical {
    if (status == OrderStatus.completed || status == OrderStatus.cancelled) {
      return true;
    }
    final s = scheduledAt;
    if (s != null && s.isBefore(DateTime.now())) return true;
    return false;
  }

  /// Заказ активный — обратное к [isHistorical].
  bool get isActive => !isHistorical;

  /// Просроченный «размещённый» заказ: исполнитель не найден, а назначенная
  /// дата уже прошла. Такие заказы не показываются нигде — автоматически
  /// удаляются.
  bool get isExpiredOpen {
    if (status != OrderStatus.open) return false;
    final s = scheduledAt;
    return s != null && s.isBefore(DateTime.now());
  }
}
