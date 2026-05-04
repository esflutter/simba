import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/models.dart';

class MockData {
  MockData._();

  static final Random _rng = Random();

  /// Уникальный ID заказа на стороне клиента до подключения бэкенда.
  /// epoch + 64-битный random — коллизии практически невозможны даже
  /// при одновременных публикациях из тестовой автоматизации.
  static String generateOrderId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = _rng.nextInt(1 << 32).toRadixString(36);
    return 'm${ts}_$rnd';
  }

  static const List<City> cities = [
    City(id: 'msk', name: 'Москва', center: LatLng(55.7558, 37.6173)),
    City(id: 'spb', name: 'Санкт-Петербург', center: LatLng(59.9343, 30.3351)),
    City(id: 'nsk', name: 'Новосибирск', center: LatLng(55.0084, 82.9357)),
    City(id: 'ekb', name: 'Екатеринбург', center: LatLng(56.8389, 60.6057)),
    City(id: 'kzn', name: 'Казань', center: LatLng(55.8304, 49.0661)),
    City(id: 'nn', name: 'Нижний Новгород', center: LatLng(56.2965, 43.9361)),
    City(id: 'chl', name: 'Челябинск', center: LatLng(55.1644, 61.4368)),
    City(id: 'sam', name: 'Самара', center: LatLng(53.1959, 50.1002)),
    City(id: 'omk', name: 'Омск', center: LatLng(54.9885, 73.3242)),
    City(id: 'rnd', name: 'Ростов-на-Дону', center: LatLng(47.2357, 39.7015)),
    City(id: 'ufa', name: 'Уфа', center: LatLng(54.7388, 55.9721)),
    City(id: 'krs', name: 'Красноярск', center: LatLng(56.0153, 92.8932)),
    City(id: 'vrn', name: 'Воронеж', center: LatLng(51.6608, 39.2003)),
    City(id: 'prm', name: 'Пермь', center: LatLng(58.0105, 56.2502)),
    City(id: 'vlg', name: 'Волгоград', center: LatLng(48.708, 44.5133)),
    City(id: 'krd', name: 'Краснодар', center: LatLng(45.0355, 38.9753)),
    City(id: 'srt', name: 'Саратов', center: LatLng(51.5924, 46.0348)),
    City(id: 'tum', name: 'Тюмень', center: LatLng(57.1522, 65.5272)),
  ];

  static const List<Category> categories = [
    Category(id: 'home', name: 'Бытовые работы', icon: 'spanner'),
    Category(id: 'snow', name: 'Уборка снега', icon: 'gallery'),
    Category(id: 'delivery', name: 'Срочная доставка', icon: 'truck'),
    Category(id: 'garden', name: 'Сад и огород', icon: 'spanner'),
    Category(id: 'cleaning', name: 'Уборка и клининг', icon: 'gallery'),
    Category(id: 'repair', name: 'Мелкий ремонт', icon: 'spanner'),
    Category(id: 'help_old', name: 'Помощь пожилым', icon: 'support'),
    Category(id: 'other', name: 'Другое', icon: 'add'),
  ];

  static const List<String> reviewTags = [
    'Вежливый', 'Аккуратный', 'Надёжный', 'Пунктуальный',
    'Внимательный', 'Опытный', 'Быстрый', 'Дружелюбный',
  ];

  static final AppUser demoCurrentUser = AppUser(
    id: 'me',
    name: 'Иван Иванов',
    phone: '+7(900) 123-45-67',
    rating: 4.9,
    reviewsCount: 23,
    cityId: 'msk',
  );

  static final List<AppUser> otherUsers = [
    const AppUser(id: 'u1', name: 'Алексей К.', phone: '+7(900) 111-22-33', rating: 4.8, reviewsCount: 14),
    const AppUser(id: 'u2', name: 'Мария С.', phone: '+7(900) 222-33-44', rating: 4.7, reviewsCount: 9),
    const AppUser(id: 'u3', name: 'Дмитрий П.', phone: '+7(900) 333-44-55', rating: 5.0, reviewsCount: 31),
    const AppUser(id: 'u4', name: 'Елена В.', phone: '+7(900) 444-55-66', rating: 4.6, reviewsCount: 6),
  ];

  static List<Order> seedOrders(LatLng cityCenter) {
    final now = DateTime.now();
    return [
      Order(
        id: 'o1',
        customerId: 'u1',
        categoryId: 'snow',
        title: 'Расчистить двор от снега',
        description: 'Двор частного дома, ~80 м². Нужно почистить дорожки и подъезд к воротам.',
        address: 'ул. Тверская, 12',
        location: LatLng(cityCenter.latitude + 0.01, cityCenter.longitude + 0.005),
        priceRub: 3000,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(minutes: 12)),
      ),
      Order(
        id: 'o2',
        customerId: 'u2',
        categoryId: 'delivery',
        title: 'Доставить запчасть на СТО',
        description: 'Забрать детальку из магазина и привезти на СТО. ~7 км.',
        address: 'пр-т Мира, 3',
        location: LatLng(cityCenter.latitude - 0.012, cityCenter.longitude + 0.008),
        priceRub: 700,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 1)),
        scheduledAt: now.add(const Duration(days: 1)),
        asap: false,
      ),
      Order(
        id: 'o3',
        customerId: 'u3',
        categoryId: 'home',
        title: 'Собрать каркас теплицы',
        description: 'Каркас из профильной трубы, всё уже куплено и лежит в огороде.',
        address: 'СНТ Берёзка, 14',
        location: LatLng(cityCenter.latitude + 0.02, cityCenter.longitude - 0.015),
        priceRub: 5000,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      Order(
        id: 'o4',
        customerId: 'u4',
        categoryId: 'garden',
        title: 'Выкосить траву на участке',
        description: 'Триммер свой нужен. Участок 6 соток.',
        address: 'д. Малые Вязёмы',
        location: LatLng(cityCenter.latitude - 0.018, cityCenter.longitude - 0.012),
        priceRub: 2500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      Order(
        id: 'o5',
        customerId: 'u1',
        categoryId: 'cleaning',
        title: 'Уборка после ремонта',
        description: '2-комнатная квартира, 60 м².',
        address: 'ул. Ленина, 45',
        location: LatLng(cityCenter.latitude + 0.005, cityCenter.longitude + 0.018),
        priceRub: 4500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
    ];
  }

  static List<Order> seedMyOrders(LatLng cityCenter) {
    final now = DateTime.now();
    return [
      Order(
        id: 'm1',
        customerId: 'me',
        categoryId: 'snow',
        title: 'Расчистить дорожки',
        description: 'Двор, дорожки, подъезд к гаражу.',
        address: 'ул. Садовая, 7',
        location: LatLng(cityCenter.latitude + 0.008, cityCenter.longitude + 0.003),
        priceRub: 3000,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(minutes: 30)),
        responses: const ['u1', 'u2', 'u3'],
      ),
      Order(
        id: 'm2',
        customerId: 'me',
        categoryId: 'delivery',
        title: 'Привезти продукты',
        description: 'Список в комментариях.',
        address: 'пр-т Победы, 18',
        location: LatLng(cityCenter.latitude - 0.005, cityCenter.longitude + 0.01),
        priceRub: 800,
        status: OrderStatus.accepted,
        createdAt: now.subtract(const Duration(hours: 2)),
        executorId: 'u1',
      ),
      Order(
        id: 'm3',
        customerId: 'me',
        categoryId: 'repair',
        title: 'Заменить смеситель',
        description: 'Кухня. Смеситель куплен.',
        address: 'ул. Гагарина, 9',
        location: LatLng(cityCenter.latitude + 0.002, cityCenter.longitude - 0.004),
        priceRub: 2000,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 3)),
        executorId: 'u3',
      ),
    ];
  }

  static List<Review> seedReviews() => [
        Review(
          id: 'r1', fromUserId: 'u1', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Отлично выполнил работу, аккуратно и в срок.',
          tags: const ['Вежливый', 'Аккуратный', 'Пунктуальный'],
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        Review(
          id: 'r2', fromUserId: 'u2', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Спасибо за помощь!', tags: const ['Надёжный'],
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        Review(
          id: 'r3', fromUserId: 'u3', toUserId: 'me', orderId: 'm3',
          rating: 4, comment: 'Всё хорошо, но чуть задержался.', tags: const ['Аккуратный'],
          createdAt: DateTime.now().subtract(const Duration(days: 14)),
        ),
      ];
}
