import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/core/utils/async_lock.dart';

void main() {
  group('AsyncLock', () {
    test('executes blocks sequentially for the same key', () async {
      final executionOrder = <int>[];

      final future1 = AsyncLock.run('test_key', () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        executionOrder.add(1);
        return 1;
      });

      final future2 = AsyncLock.run('test_key', () async {
        executionOrder.add(2);
        return 2;
      });

      final results = await Future.wait([future1, future2]);

      expect(results, [1, 2]);
      expect(executionOrder, [1, 2]);
    });

    test('executes blocks concurrently for different keys', () async {
      final executionOrder = <int>[];

      final future1 = AsyncLock.run('key_a', () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        executionOrder.add(1);
      });

      final future2 = AsyncLock.run('key_b', () async {
        executionOrder.add(2);
      });

      await Future.wait([future1, future2]);

      // key_b has no delay, so it should finish before key_a
      expect(executionOrder, [2, 1]);
    });

    test('propagates errors and unlocks next task', () async {
      var secondTaskRan = false;

      final future1 = AsyncLock.run('error_key', () async {
        throw StateError('Task 1 failed');
      });

      final future2 = AsyncLock.run('error_key', () async {
        secondTaskRan = true;
        return 'success';
      });

      expect(future1, throwsStateError);
      final result2 = await future2;

      expect(secondTaskRan, isTrue);
      expect(result2, 'success');
    });
  });
}
