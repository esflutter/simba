import 'package:flutter_test/flutter_test.dart';
import 'package:simba/core/utils/realtime_throttle.dart';

void main() {
  group('RealtimeThrottle', () {
    test('первое событие выполняется сразу (leading edge)', () {
      final t = RealtimeThrottle(window: const Duration(milliseconds: 50));
      var calls = 0;
      t.run(() => calls++);
      // Мгновенно, без ожидания таймера — это и есть «реалтайм».
      expect(calls, 1);
      t.dispose();
    });

    test('всплеск за окно склеивается в один догоняющий вызов', () async {
      final t = RealtimeThrottle(window: const Duration(milliseconds: 30));
      var calls = 0;
      void action() => calls++;
      t.run(action); // leading → 1
      t.run(action); // в окне → копится trailing
      t.run(action); // в окне → тот же trailing
      expect(calls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      // Один догоняющий, а не три.
      expect(calls, 2);
      t.dispose();
    });

    test('события с паузой больше окна — каждое мгновенно, без догоняющих',
        () async {
      final t = RealtimeThrottle(window: const Duration(milliseconds: 20));
      var calls = 0;
      void action() => calls++;
      t.run(action); // 1 (leading)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      t.run(action); // окно истекло без trailing → снова leading → 2
      expect(calls, 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Лишних догоняющих нет.
      expect(calls, 2);
      t.dispose();
    });

    test('dispose отменяет отложенный догоняющий вызов', () async {
      final t = RealtimeThrottle(window: const Duration(milliseconds: 30));
      var calls = 0;
      void action() => calls++;
      t.run(action); // 1 (leading)
      t.run(action); // trailing pending
      t.dispose(); // отменяет таймер
      await Future<void>.delayed(const Duration(milliseconds: 70));
      // Догоняющий не сработал.
      expect(calls, 1);
    });
  });
}
