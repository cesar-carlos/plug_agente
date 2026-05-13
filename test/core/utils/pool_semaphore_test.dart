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

    test('should wake queued acquirers when resized up', () async {
      final semaphore = PoolSemaphore(1);
      await semaphore.acquire();

      var secondAcquired = false;
      final secondAcquire = semaphore.acquire().then((_) {
        secondAcquired = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      semaphore.resize(2);
      await secondAcquire;

      expect(secondAcquired, isTrue);
      expect(semaphore.maxConcurrent, 2);
      expect(semaphore.activeCount, 2);
    });

    test('should not grant new permits above reduced capacity until releases catch up', () async {
      final semaphore = PoolSemaphore(2);
      await semaphore.acquire();
      await semaphore.acquire();
      semaphore.resize(1);

      await expectLater(
        semaphore.acquire(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );

      semaphore.release();
      await expectLater(
        semaphore.acquire(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );

      semaphore.release();
      await semaphore.acquire(timeout: const Duration(milliseconds: 20));
      expect(semaphore.activeCount, 1);
    });
  });
}
