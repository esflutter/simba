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

/// Способ расчёта по заказу. Оплаты внутри приложения нет — оба варианта
/// подразумевают расчёт напрямую между заказчиком и исполнителем на месте.
enum PaymentMethod {
  /// Наличными при встрече.
  cash,

  /// Безналичный перевод на месте (СБП / перевод по номеру / карта на карту).
  cashlessTransfer,
}

extension PaymentMethodMapping on PaymentMethod {
  /// Ключ для коллекции `orders.payment_method` в PocketBase.
  /// Значения совпадают с enum-values в миграции 003 + расширение в 019.
  String get dbValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.cashlessTransfer:
        return 'cashless_transfer';
    }
  }

  /// Человекочитаемая подпись для UI (карточка деталей, экран выбора).
  /// Один и тот же текст должен показываться везде, поэтому держим его
  /// здесь, а не дублируем по экранам.
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Наличными исполнителю';
      case PaymentMethod.cashlessTransfer:
        return 'Безналичным переводом на месте';
    }
  }

  /// Парсит значение из БД. Неизвестное — `cash` с пометкой в логе,
  /// чтобы не падать при расширении словаря на бэке без согласования.
  static PaymentMethod fromDbValue(String? raw) {
    switch (raw) {
      case 'cash':
        return PaymentMethod.cash;
      case 'cashless_transfer':
        return PaymentMethod.cashlessTransfer;
      default:
        if (raw != null && raw.isNotEmpty) {
          debugPrint('[PaymentMethod] unknown db value "$raw" — fallback to cash');
        }
        return PaymentMethod.cash;
    }
  }

  /// Парсит обратно из UI-подписи (например, после выбора в bottom sheet,
  /// который хранит выбранное значение строкой). Тот же fallback.
  static PaymentMethod fromLabel(String? label) {
    for (final m in PaymentMethod.values) {
      if (m.label == label) return m;
    }
    return PaymentMethod.cash;
  }
}

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
    this.relistedAt,
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

  /// Момент возврата заказа в ленту после отказа исполнителя
  /// (`accepted → open`). Серверный хук ставит сюда `now` при таком
  /// переходе; миграция 028 добавила это поле. Используется как точка
  /// отсчёта для 30-дневной авто-чистки: иначе заказ, принятый на
  /// 29-й день и отвергнутый на 30-й, удалялся бы буквально на
  /// следующий день. На моках всегда null (мок-флоу не пересоздаёт
  /// эту метку), для свежесозданных заказов — тоже null.
  final DateTime? relistedAt;

  /// Sentinel-паттерн для nullable-полей (см. [AppUser.copyWith]):
  /// явный `null` действительно очищает поле, а не игнорируется
  /// (как было бы при `?? this.field`). Нужно, например, чтобы при
  /// отказе исполнителя сбросить `executorId: null`.
  Order copyWith({
    OrderStatus? status,
    Object? executorId = _sentinel,
    List<String>? responses,
    Object? scheduledAt = _sentinel,
    int? priceRub,
    Object? completedAt = _sentinel,
    Object? workDoneAt = _sentinel,
    Object? workConfirmedAt = _sentinel,
    Object? paymentReceivedAt = _sentinel,
    Object? cityId = _sentinel,
    Object? relistedAt = _sentinel,
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
        scheduledAt: identical(scheduledAt, _sentinel)
            ? this.scheduledAt
            : scheduledAt as DateTime?,
        asap: asap,
        executorId: identical(executorId, _sentinel)
            ? this.executorId
            : executorId as String?,
        photoPaths: photoPaths,
        responses: responses ?? this.responses,
        paymentMethod: paymentMethod,
        forOtherPhone: forOtherPhone,
        customerName: customerName,
        customerPhotoUrl: customerPhotoUrl,
        executorName: executorName,
        executorPhotoUrl: executorPhotoUrl,
        categoryName: categoryName,
        completedAt: identical(completedAt, _sentinel)
            ? this.completedAt
            : completedAt as DateTime?,
        workDoneAt: identical(workDoneAt, _sentinel)
            ? this.workDoneAt
            : workDoneAt as DateTime?,
        workConfirmedAt: identical(workConfirmedAt, _sentinel)
            ? this.workConfirmedAt
            : workConfirmedAt as DateTime?,
        paymentReceivedAt: identical(paymentReceivedAt, _sentinel)
            ? this.paymentReceivedAt
            : paymentReceivedAt as DateTime?,
        cityId: identical(cityId, _sentinel)
            ? this.cityId
            : cityId as String?,
        relistedAt: identical(relistedAt, _sentinel)
            ? this.relistedAt
            : relistedAt as DateTime?,
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
    this.fromUserName = '',
    this.fromUserPhotoUrl,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String orderId;
  final int rating;
  final String comment;
  final List<String> tags;
  final DateTime createdAt;

  /// Имя автора отзыва, если PB вернул `expand.from_user.name`.
  /// Пусто, если expand не подгружен (например, мок-режим) — UI
  /// сваливается на `userById` или «Пользователь».
  final String fromUserName;

  /// URL аватарки автора. Заполняется из `expand.from_user.photo`
  /// через `pb.files.getUrl()`. Null, если фото не загружено или
  /// expand не пришёл.
  final String? fromUserPhotoUrl;
}

/// Slug → русская подпись для review-тегов. Сторятся на бэке в коллекции
/// `review_tags` (миграция 1700000007). Если в БД оказался слаг, которого
/// здесь нет (например, старый seed заливал `quality`/`professional`/
/// `thorough` — не из списка), UI покажет слаг как есть.
const Map<String, String> kReviewTagRu = {
  'polite': 'Вежливый',
  'accurate': 'Аккуратный',
  'reliable': 'Надёжный',
  'punctual': 'Пунктуальный',
  'attentive': 'Внимательный',
  'experienced': 'Опытный',
  'fast': 'Быстрый',
  'friendly': 'Дружелюбный',
};

String reviewTagLabel(String slug) => kReviewTagRu[slug] ?? slug;

extension OrderLifecycle on Order {
  /// Заказ относится к истории: завершён, отменён, либо запланированная
  /// дата начала уже прошла (наступило указанное время и позже).
  ///
  /// NB: для целей UI «у меня в истории» используются per-side флаги
  /// [isCompletedByCustomer] / [isCompletedByExecutor] — после переезда
  /// FSM на схему «два независимых флоу»: заказ попадает в историю
  /// стороны, как только ОНА отметила свою часть, независимо от того,
  /// отметила ли другая сторона.
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

  /// Заказ висит без исполнителя «слишком долго» — на сервере его
  /// удаляет ночная задача `delete-stale-open-orders` (см.
  /// `backend/pb_hooks/main.pb.js`, миграция 026). Срок настраивается
  /// в коллекции `settings` (`order.delete_stale_days`, дефолт 30 дней).
  /// Если заказ возвращался в ленту после отказа исполнителя, отсчёт
  /// идёт от `relisted_at` (миграция 028), иначе — от `created`.
  ///
  /// Клиент держит эту проверку как «защитную сетку»: если устройство
  /// давно не открывали и в кэше остались протухшие заказы, мы их
  /// прячем из лент локально. Сервер — источник правды.
  ///
  /// Константа 60 — намеренно с запасом относительно серверного дефолта
  /// 30: если админ поменяет серверный TTL на 45 или 60, клиент не
  /// начнёт преждевременно прятать ещё живые заказы. Если на сервере
  /// поставят >60 — клиент будет скрывать раньше; это известный лимит
  /// MVP, для полной синхронизации нужен публичный эндпоинт настроек.
  bool get isStaleOpenWithoutExecutor {
    if (status != OrderStatus.open) return false;
    if (executorId != null) return false;
    // Берём максимум из createdAt и relistedAt — для заказов, которые
    // возвращались в ленту после отказа исполнителя, точка отсчёта —
    // момент возврата, иначе — момент публикации.
    final baseline = relistedAt ?? createdAt;
    final age = DateTime.now().difference(baseline);
    return age.inDays >= 60;
  }

  /// Наступило ли время начала работы. Для ASAP и заказов без даты —
  /// всегда `true` (по схеме ТЗ «время заказа наступило ИЛИ заказ без даты»).
  /// Используется как gate в UI: до наступления — доступна отмена,
  /// после — кнопки выполнения.
  bool get isTimeArrived {
    final s = scheduledAt;
    if (s == null || asap) return true;
    return !s.toLocal().isAfter(DateTime.now());
  }

  /// Заказчик уже отметил «работа выполнена» по этому заказу.
  /// Источник истины — серверная метка [workConfirmedAt]. На моках
  /// зеркалится туда же.
  bool get isCompletedByCustomer => workConfirmedAt != null;

  /// Исполнитель уже отметил «оплата получена».
  bool get isCompletedByExecutor => paymentReceivedAt != null;

  /// Глобально-завершённый заказ: обе стороны отметили свою часть.
  /// На бэке этому соответствует статус `completed`. Клиент может
  /// принимать решение и без статуса — по двум флагам.
  bool get isFullyCompleted =>
      isCompletedByCustomer && isCompletedByExecutor;

  /// Может ли заказчик ещё отменить заказ. По схеме ТЗ:
  /// - в статусе `open` — всегда (исполнитель ещё не выбран);
  /// - в статусе `accepted` — пока время не наступило и НИ ОДНА из трёх
  ///   FSM-меток не выставлена. Сервер проверяет ровно эти три поля
  ///   (см. миграция 027 и хук `onRecordDelete("orders")` в
  ///   main.pb.js); клиентская проверка должна совпадать, иначе UI
  ///   разрешит тап «Отменить», а сервер вернёт ошибку.
  bool canCancelByCustomer() {
    if (status == OrderStatus.open) return true;
    if (status != OrderStatus.accepted) return false;
    if (workDoneAt != null ||
        workConfirmedAt != null ||
        paymentReceivedAt != null) {
      return false;
    }
    return !isTimeArrived;
  }

  /// Может ли исполнитель отменить заказ. По схеме ТЗ доступно
  /// только в статусе `accepted` до наступления времени и до того,
  /// как кто-то отметил свою часть. Условие на FSM-метки симметрично
  /// `canCancelByCustomer` — серверная сторона тоже не пустит, если
  /// исполнитель пробует отказаться после своей отметки work_done.
  bool canCancelByExecutor() {
    if (status != OrderStatus.accepted) return false;
    if (workDoneAt != null ||
        workConfirmedAt != null ||
        paymentReceivedAt != null) {
      return false;
    }
    return !isTimeArrived;
  }
}
