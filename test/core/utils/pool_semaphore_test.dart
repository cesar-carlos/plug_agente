import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';

void main() {
  group('PoolSemaphore', () {
    test('should allow up to max concurrent acquires', () async {
      final semaphore = PoolSemaphore(2);
      await semaphore.acquire();
      await semaphore.acquire();

      var thirdAcquired = false;
      final thirdAcquire = semaphore.acquire().then((_) {
        thirdAcquired = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(thirdAcquired, isFalse);

      semaphore.release();
      await thirdAcquire;
      expect(thirdAcquired, isTrue);
    });

    test('should throw timeout when no permit is released', () async {
      final semaphore = PoolSemaphore(1);
      await semaphore.acquire();

      expect(
        semaphore.acquire(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('release with empty queue should not exceed capacity', () async {
      final semaphore = PoolSemaphore(1);

      semaphore.release();
      await semaphore.acquire();

      expect(
        semaphore.acquire(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
