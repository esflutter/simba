import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/client_uid.dart';

void main() {
  group('generateClientUid — формат UUID v4', () {
    test('длина 36 (8-4-4-4-12 + 4 дефиса)', () {
      final id = generateClientUid();
      expect(id.length, 36);
    });

    test('5 групп через дефис, ширины 8/4/4/4/12', () {
      final id = generateClientUid();
      final parts = id.split('-');
      expect(parts.length, 5);
      expect(parts[0].length, 8);
      expect(parts[1].length, 4);
      expect(parts[2].length, 4);
      expect(parts[3].length, 4);
      expect(parts[4].length, 12);
    });

    test('только hex-символы [0-9a-f]', () {
      final id = generateClientUid();
      expect(RegExp(r'^[0-9a-f-]+$').hasMatch(id), isTrue, reason: id);
    });

    test('версия 4 — 13-й hex-символ равен "4"', () {
      // UUID-формат: xxxxxxxx-xxxx-Mxxx-Nxxx-xxxxxxxxxxxx
      // M = версия (4 для random), 14-й символ оригинального
      // несжатого hex'а. В формате с дефисами он на позиции 14
      // (после "8-4-1" = 14 = "M").
      for (var i = 0; i < 20; i++) {
        final id = generateClientUid();
        expect(id[14], '4', reason: id);
      }
    });

    test('вариант RFC 4122 — 17-й hex-символ в {8,9,a,b}', () {
      for (var i = 0; i < 20; i++) {
        final id = generateClientUid();
        final n = id[19];
        expect(['8', '9', 'a', 'b'].contains(n), isTrue,
            reason: 'id=$id, byte17=$n');
      }
    });

    test('1000 вызовов — все уникальны', () {
      // Тест на качество источника энтропии. С Random.secure
      // коллизии практически невозможны при разумных n.
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(generateClientUid());
      }
      expect(ids.length, 1000);
    });
  });
}
