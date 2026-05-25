import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simba/core/utils/order_display.dart';
import 'package:simba/data/mock/mock_data.dart';
import 'package:simba/data/models/models.dart';

Order _ord({
  String categoryId = 'snow',
  String? categoryName,
}) =>
    Order(
      id: 'o',
      customerId: 'me',
      categoryId: categoryId,
      title: '',
      description: '',
      address: '',
      location: const LatLng(55, 37),
      priceRub: 100,
      status: OrderStatus.open,
      createdAt: DateTime.now(),
      categoryName: categoryName,
    );

void main() {
  group('categoryNameOf', () {
    test('expand.category.name приходит с бэка → используется напрямую', () {
      final o = _ord(categoryId: 'unknown_one', categoryName: 'Спецкатегория');
      expect(categoryNameOf(o), 'Спецкатегория');
    });

    test('fallback на справочник по categoryId', () {
      // 'snow' — один из стандартных id в MockData.categories.
      final mock = MockData.categories.firstWhere((c) => c.id == 'snow');
      final o = _ord(categoryId: 'snow');
      expect(categoryNameOf(o), mock.name);
    });

    test('неизвестный id → последняя категория-«Другое»', () {
      final o = _ord(categoryId: 'totally_unknown_xyz');
      expect(categoryNameOf(o), MockData.categories.last.name);
    });

    test('expand-имя в приоритете даже над известным id', () {
      // Бэкенд может прислать новое имя — оно должно перекрывать локальный
      // справочник, иначе при ребрендинге категорий клиент будет показывать
      // устаревшее «снежные работы», а сервер — «Уборка снега».
      final o = _ord(categoryId: 'snow', categoryName: 'Новое название');
      expect(categoryNameOf(o), 'Новое название');
    });

    test('пустое expand-имя считается отсутствующим → fallback', () {
      final o = _ord(categoryId: 'snow', categoryName: '');
      final mock = MockData.categories.firstWhere((c) => c.id == 'snow');
      expect(categoryNameOf(o), mock.name);
    });
  });
}
