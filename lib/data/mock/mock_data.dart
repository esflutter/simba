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

  /// 13 городов-миллионников РФ (по убыванию населения 2024). Список
  /// должен совпадать с seed-данными в `backend/pb_migrations/1700000007_*`.
  /// При расширении на агломерации/области: добавляй города сюда + seed,
  /// `boundsRadiusKm` подбирай по реальной географии (Москва 60, Воронеж 40),
  /// `dadataFiasId` — `city_fias_id` из DaData /suggest по названию.
  static const List<City> cities = [
    City(id: 'msk', name: 'Москва',          center: LatLng(55.7558, 37.6173), dadataFiasId: '0c5b2444-70a0-4932-980c-b4dc0d3f02b5', boundsRadiusKm: 60),
    City(id: 'spb', name: 'Санкт-Петербург', center: LatLng(59.9343, 30.3351), dadataFiasId: 'c2deb16a-0330-4f05-821f-1d09c93331e6', boundsRadiusKm: 55),
    City(id: 'nsk', name: 'Новосибирск',     center: LatLng(55.0084, 82.9357), dadataFiasId: '8dea00e3-9aab-4d8e-887c-ef2aaa546456', boundsRadiusKm: 45),
    City(id: 'ekb', name: 'Екатеринбург',    center: LatLng(56.8389, 60.6057), dadataFiasId: '2763c110-cb8b-416a-9dac-ad28a55b4402', boundsRadiusKm: 50),
    City(id: 'kzn', name: 'Казань',          center: LatLng(55.8304, 49.0661), dadataFiasId: '93b3df57-4c89-44df-ac42-96f05e9cd3b9', boundsRadiusKm: 45),
    City(id: 'nn',  name: 'Нижний Новгород', center: LatLng(56.2965, 43.9361), dadataFiasId: '555e7d61-d9a7-4ba6-9770-6caa8198c483', boundsRadiusKm: 40),
    City(id: 'krs', name: 'Красноярск',      center: LatLng(56.0153, 92.8932), dadataFiasId: '9b968c73-f4d4-41c2-8e0c-2e3f4e3f4b6c', boundsRadiusKm: 45),
    City(id: 'chl', name: 'Челябинск',       center: LatLng(55.1644, 61.4368), dadataFiasId: 'a376e68d-724a-4472-be7c-7bb38e2cf6bd', boundsRadiusKm: 40),
    City(id: 'sam', name: 'Самара',          center: LatLng(53.1959, 50.1002), dadataFiasId: 'bb035cc3-1dc2-4627-9d25-a1bf2d4b936b', boundsRadiusKm: 40),
    City(id: 'ufa', name: 'Уфа',             center: LatLng(54.7388, 55.9721), dadataFiasId: '7339e834-2cb4-4734-a4c7-1fca2c66e562', boundsRadiusKm: 40),
    City(id: 'rnd', name: 'Ростов-на-Дону',  center: LatLng(47.2357, 39.7015), dadataFiasId: 'c1cfe4b6-c01d-4ac0-a06b-1a41e159f6f9', boundsRadiusKm: 40),
    City(id: 'krd', name: 'Краснодар',       center: LatLng(45.0355, 38.9753), dadataFiasId: '7dfa745e-aa19-4688-b121-b73ecb14b610', boundsRadiusKm: 40),
    City(id: 'omk', name: 'Омск',            center: LatLng(54.9885, 73.3242), dadataFiasId: '140e31da-27bf-4519-9ea0-6185d681d44e', boundsRadiusKm: 40),
  ];

  static const List<Category> categories = [
    Category(id: 'delivery', name: 'Курьер и доставка', icon: 'truck_fast'),
    Category(id: 'garden', name: 'Сад и огород', icon: 'tree'),
    Category(id: 'cleaning', name: 'Уборка квартиры', icon: 'broom'),
    Category(id: 'furniture', name: 'Сборка мебели', icon: 'box'),
    Category(id: 'moving', name: 'Грузоперевозки', icon: 'truck'),
    Category(id: 'repair', name: 'Мелкий ремонт', icon: 'hammer'),
    Category(id: 'plumbing', name: 'Сантехника', icon: 'drop'),
    Category(id: 'electric', name: 'Электрика', icon: 'flash'),
    Category(id: 'elderly', name: 'Помощь пожилым', icon: 'support'),
    Category(id: 'pets', name: 'Уход за животными', icon: 'pet'),
    Category(id: 'auto', name: 'Авто-помощь', icon: 'car'),
    Category(id: 'computer', name: 'Компьютерная помощь', icon: 'monitor'),
    Category(id: 'snow', name: 'Уборка снега', icon: 'snowflake'),
    Category(id: 'other', name: 'Другое', icon: 'add'),
  ];

  static const List<String> reviewTags = [
    'Вежливый', 'Аккуратный', 'Надёжный', 'Пунктуальный',
    'Внимательный', 'Опытный', 'Быстрый', 'Дружелюбный',
  ];

  static final AppUser demoCurrentUser = AppUser(
    id: 'me',
    name: 'Иван Иванов',
    phone: '+7 (900) 123-45-67',
    rating: 4.9,
    reviewsCount: 23,
    cityId: 'msk',
  );

  static final List<AppUser> otherUsers = [
    const AppUser(id: 'u1', name: 'Алексей К.', phone: '+7 (900) 111-22-33', rating: 4.8, reviewsCount: 14),
    const AppUser(id: 'u2', name: 'Мария С.', phone: '+7 (900) 222-33-44', rating: 4.7, reviewsCount: 9),
    const AppUser(id: 'u3', name: 'Дмитрий П.', phone: '+7 (900) 333-44-55', rating: 5.0, reviewsCount: 31),
    const AppUser(id: 'u4', name: 'Елена В.', phone: '+7 (900) 444-55-66', rating: 4.6, reviewsCount: 6),
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
        categoryId: 'garden',
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
        scheduledAt: DateTime(now.year, now.month, now.day, 18, 30)
            .add(const Duration(days: 1)),
        asap: false,
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
      Order(
        id: 'm4',
        customerId: 'me',
        categoryId: 'cleaning',
        title: 'Уборка после ремонта',
        description: 'Двушка ~60 м², пыль и строймусор.',
        address: 'ул. Лесная, 22',
        location: LatLng(cityCenter.latitude + 0.011, cityCenter.longitude - 0.006),
        priceRub: 4500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 5)),
        scheduledAt: DateTime(now.year, now.month, now.day, 10, 0)
            .add(const Duration(days: 3)),
        asap: false,
        responses: const ['u2'],
      ),
      Order(
        id: 'm5',
        customerId: 'me',
        categoryId: 'furniture',
        title: 'Собрать кухонный гарнитур',
        description: 'Икея, инструкция есть. Шуруповёрт нужен свой.',
        address: 'ул. Молодёжная, 14',
        location: LatLng(cityCenter.latitude - 0.009, cityCenter.longitude + 0.007),
        priceRub: 6500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 1)),
        scheduledAt: DateTime(now.year, now.month, now.day, 14, 0)
            .add(const Duration(days: 7)),
        asap: false,
      ),
      Order(
        id: 'm6',
        customerId: 'me',
        categoryId: 'garden',
        title: 'Постричь газон у дачи',
        description: 'Участок 8 соток, газонокосилка есть.',
        address: 'СНТ Радуга, 42',
        location: LatLng(cityCenter.latitude + 0.018, cityCenter.longitude + 0.014),
        priceRub: 2500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      Order(
        id: 'm7',
        customerId: 'me',
        categoryId: 'electric',
        title: 'Заменить розетки в спальне',
        description: '4 точки. Розетки куплены.',
        address: 'ул. Чехова, 5',
        location: LatLng(cityCenter.latitude - 0.013, cityCenter.longitude - 0.009),
        priceRub: 1800,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(hours: 12)),
        scheduledAt: DateTime(now.year, now.month, now.day, 19, 0)
            .add(const Duration(days: 2)),
        asap: false,
      ),
      // ── Историческое: выполненные (нужно «Оставить отзыв» там, где нет review от me)
      Order(
        id: 'm8',
        customerId: 'me',
        categoryId: 'cleaning',
        title: 'Генеральная уборка',
        description: 'Трёшка после ремонта, 90 м².',
        address: 'ул. Никольская, 18',
        location: LatLng(cityCenter.latitude + 0.013, cityCenter.longitude + 0.011),
        priceRub: 5500,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        executorId: 'u2',
      ),
      Order(
        id: 'm9',
        customerId: 'me',
        categoryId: 'delivery',
        title: 'Перевезти диван',
        description: 'Диван-книжка, 2 места погрузки. Газель нужна.',
        address: 'ул. Профсоюзная, 45',
        location: LatLng(cityCenter.latitude - 0.022, cityCenter.longitude + 0.013),
        priceRub: 2200,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 2, hours: 10)),
        executorId: 'u4',
      ),
      Order(
        id: 'm10',
        customerId: 'me',
        categoryId: 'repair',
        title: 'Починить стиральную машину',
        description: 'Не отжимает. LG, 6 кг.',
        address: 'ул. Ботаническая, 9',
        location: LatLng(cityCenter.latitude + 0.016, cityCenter.longitude - 0.008),
        priceRub: 3200,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 5)),
        executorId: 'u1',
      ),
      Order(
        id: 'm11',
        customerId: 'me',
        categoryId: 'electric',
        title: 'Повесить люстру',
        description: 'Двойной выключатель, 5 рожков.',
        address: 'пер. Капельский, 4',
        location: LatLng(cityCenter.latitude + 0.004, cityCenter.longitude - 0.014),
        priceRub: 1500,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 7)),
        executorId: 'u3',
      ),
      Order(
        id: 'm12',
        customerId: 'me',
        categoryId: 'furniture',
        title: 'Собрать письменный стол',
        description: 'Hoff, инструкция в коробке.',
        address: 'ул. Дубининская, 71',
        location: LatLng(cityCenter.latitude - 0.007, cityCenter.longitude - 0.018),
        priceRub: 1700,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 14)),
        executorId: 'u2',
      ),
      Order(
        id: 'm13',
        customerId: 'me',
        categoryId: 'garden',
        title: 'Обрезать яблони',
        description: '5 деревьев, инструмент с собой.',
        address: 'СНТ Берёзка, 3',
        location: LatLng(cityCenter.latitude + 0.025, cityCenter.longitude + 0.022),
        priceRub: 3800,
        status: OrderStatus.completed,
        createdAt: now.subtract(const Duration(days: 21)),
        executorId: 'u4',
      ),
      // ── Историческое: размещённые (просроченные — НЕ выполненные)
      Order(
        id: 'm16',
        customerId: 'me',
        categoryId: 'delivery',
        title: 'Забрать посылку с СДЭК',
        description: 'Пункт выдачи на Тверской.',
        address: 'ул. Тверская, 22',
        location: LatLng(cityCenter.latitude + 0.001, cityCenter.longitude - 0.005),
        priceRub: 500,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(days: 4)),
        scheduledAt: now.subtract(const Duration(days: 2, hours: 6)),
        asap: false,
      ),
      Order(
        id: 'm18',
        customerId: 'me',
        categoryId: 'electric',
        title: 'Перенести розетку на кухне',
        description: 'Передвинуть на 30 см вправо.',
        address: 'Ленинский пр-т, 78',
        location: LatLng(cityCenter.latitude - 0.016, cityCenter.longitude - 0.020),
        priceRub: 1600,
        status: OrderStatus.open,
        createdAt: now.subtract(const Duration(days: 9)),
        scheduledAt: now.subtract(const Duration(days: 6)),
        asap: false,
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
        Review(
          id: 'r6', fromUserId: 'u4', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Чисто и аккуратно, прибрал за собой.',
          tags: const ['Аккуратный', 'Вежливый'],
          createdAt: DateTime.now().subtract(const Duration(days: 18)),
        ),
        Review(
          id: 'r7', fromUserId: 'u1', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Хороший мастер, рекомендую.',
          tags: const ['Профессионал'],
          createdAt: DateTime.now().subtract(const Duration(days: 22)),
        ),
        Review(
          id: 'r8', fromUserId: 'u2', toUserId: 'me', orderId: 'm3',
          rating: 4, comment: 'Сделал хорошо, но чуть дольше планируемого.',
          tags: const ['Аккуратный'],
          createdAt: DateTime.now().subtract(const Duration(days: 28)),
        ),
        Review(
          id: 'r9', fromUserId: 'u3', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Всё отлично, советую всем!',
          tags: const ['Профессионал', 'Пунктуальный'],
          createdAt: DateTime.now().subtract(const Duration(days: 31)),
        ),
        Review(
          id: 'r10', fromUserId: 'u4', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Договорились без проблем, выполнил быстро.',
          tags: const ['Надёжный'],
          createdAt: DateTime.now().subtract(const Duration(days: 35)),
        ),
        Review(
          id: 'r11', fromUserId: 'u1', toUserId: 'me', orderId: 'm3',
          rating: 3, comment: 'Нормально, но качество могло быть лучше.',
          tags: const [],
          createdAt: DateTime.now().subtract(const Duration(days: 42)),
        ),
        Review(
          id: 'r12', fromUserId: 'u2', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Профи. Спасибо за работу.',
          tags: const ['Профессионал'],
          createdAt: DateTime.now().subtract(const Duration(days: 48)),
        ),
        Review(
          id: 'r13', fromUserId: 'u3', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Сделал всё в срок, претензий нет.',
          tags: const ['Пунктуальный', 'Аккуратный'],
          createdAt: DateTime.now().subtract(const Duration(days: 56)),
        ),
        Review(
          id: 'r14', fromUserId: 'u4', toUserId: 'me', orderId: 'm3',
          rating: 4, comment: 'В целом хорошо.',
          tags: const ['Вежливый'],
          createdAt: DateTime.now().subtract(const Duration(days: 64)),
        ),
        Review(
          id: 'r15', fromUserId: 'u1', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Замечательно, буду обращаться ещё.',
          tags: const ['Профессионал', 'Надёжный'],
          createdAt: DateTime.now().subtract(const Duration(days: 71)),
        ),
        Review(
          id: 'r16', fromUserId: 'u2', toUserId: 'me', orderId: 'm3',
          rating: 5, comment: 'Очень доволен результатом.',
          tags: const [],
          createdAt: DateTime.now().subtract(const Duration(days: 80)),
        ),
        Review(
          id: 'r17', fromUserId: 'u3', toUserId: 'me', orderId: 'm3',
          rating: 2, comment: 'Не понравилось — переделывал сам потом.',
          tags: const [],
          createdAt: DateTime.now().subtract(const Duration(days: 95)),
        ),
        // Отзывы «от me» — выполнены, отзыв уже оставлен
        Review(
          id: 'r4', fromUserId: 'me', toUserId: 'u1', orderId: 'm10',
          rating: 5, comment: 'Стиралка работает как новая, спасибо!',
          tags: const ['Профессионал', 'Аккуратный'],
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        Review(
          id: 'r5', fromUserId: 'me', toUserId: 'u2', orderId: 'm12',
          rating: 4, comment: 'Стол собран нормально, но затянули по времени.',
          tags: const ['Аккуратный'],
          createdAt: DateTime.now().subtract(const Duration(days: 13)),
        ),
      ];
}
