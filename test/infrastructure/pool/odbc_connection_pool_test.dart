import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
  });

  group('OdbcConnectionPool (lease)', () {
    late MockOdbcService mockService;
    late MockOdbcConnectionSettings mockSettings;
    late MetricsCollector metrics;
    late OdbcConnectionPool pool;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      metrics = MetricsCollector()..clear();
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        metricsCollector: metrics,
      );
    });

    test('should connect for each acquire with options', () async {
      var connectionCounter = 0;

      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectionCounter++;
        return Success(
          Connection(
            id: 'lease-$connectionCounter',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });

      final first = await pool.acquire('DSN=Test');
      final second = await pool.acquire('DSN=Test');

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      verify(
        () => mockService.connect(
          'DSN=Test',
          options: any(named: 'options'),
        ),
      ).called(2);
    });

    test('should honor custom connection options on acquire', () async {
      const customOptions = ConnectionAcquireOptions(
        queryTimeout: Duration(seconds: 12),
        maxResultBufferBytes: 64 * 1024 * 1024,
      );
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-custom',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );

      final acquired = await pool.acquire(
        'DSN=Test',
        options: customOptions,
      );

      expect(acquired.isSuccess(), isTrue);
      final capturedOptions =
          verify(
                () => mockService.connect(
                  'DSN=Test',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as ConnectionOptions;
      expect(capturedOptions.queryTimeout, customOptions.queryTimeout);
      expect(
        capturedOptions.maxResultBufferBytes,
        customOptions.maxResultBufferBytes,
      );
    });

    test('should disconnect on release and track leases', () async {
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.getOrNull(), 'lease-1');

      final activeBefore = await pool.getActiveCount();
      expect(activeBefore.getOrNull(), 1);

      final released = await pool.release('lease-1');
      expect(released.isSuccess(), isTrue);
      verify(() => mockService.disconnect('lease-1')).called(1);

      final activeAfter = await pool.getActiveCount();
      expect(activeAfter.getOrNull(), 0);
    });

    test('getActiveCount can scope leases by connection string', () async {
      var counter = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((invocation) async {
        counter++;
        final connectionString = invocation.positionalArguments.first as String;
        return Success(
          Connection(
            id: 'lease-$counter',
            connectionString: connectionString,
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      await pool.acquire('DSN=Alpha');
      await pool.acquire('DSN=Alpha');
      await pool.acquire('DSN=Beta');

      final alphaCount = await pool.getActiveCount(connectionString: 'DSN=Alpha');
      final betaCount = await pool.getActiveCount(connectionString: 'DSN=Beta');
      final allCount = await pool.getActiveCount();

      expect(alphaCount.getOrNull(), 2);
      expect(betaCount.getOrNull(), 1);
      expect(allCount.getOrNull(), 3);
    });

    test('closeAll should disconnect every leased connection', () async {
      var n = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        n++;
        return Success(
          Connection(
            id: 'id-$n',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      await pool.acquire('DSN=Test');
      await pool.acquire('DSN=Test');

      final closed = await pool.closeAll();
      expect(closed.isSuccess(), isTrue);
      verify(() => mockService.disconnect('id-1')).called(1);
      verify(() => mockService.disconnect('id-2')).called(1);
    });

    test('should enforce poolSize concurrency cap for acquires', () async {
      mockSettings.poolSize = 2;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(seconds: 1),
      );

      var connectionCounter = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectionCounter++;
        return Success(
          Connection(
            id: 'lease-$connectionCounter',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final first = await pool.acquire('DSN=Test');
      final second = await pool.acquire('DSN=Test');
      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);

      final third = pool.acquire('DSN=Test');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      verify(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).called(2);

      await pool.release(first.getOrNull()!);
      final thirdResult = await third;
      expect(thirdResult.isSuccess(), isTrue);
      verify(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('should fail acquire when semaphore timeout is reached', () async {
      mockSettings.poolSize = 1;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(milliseconds: 30),
      );

      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );

      final first = await pool.acquire('DSN=Test');
      expect(first.isSuccess(), isTrue);

      final second = await pool.acquire('DSN=Test');
      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<domain.ConnectionFailure>());
      verify(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('acquire should release the semaphore when connect throws', () async {
      mockSettings.poolSize = 1;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(milliseconds: 30),
      );

      var connectCount = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectCount++;
        if (connectCount == 1) {
          throw TimeoutException('worker busy');
        }
        return Success(
          Connection(
            id: 'lease-$connectCount',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final first = await pool.acquire('DSN=Test');
      final second = await pool.acquire('DSN=Test');

      expect(first.isError(), isTrue);
      expect(second.getOrNull(), 'lease-2');
    });

    test(
      'release should surface disconnect failure and keep the lease reserved',
      () async {
        mockSettings.poolSize = 1;
        pool = OdbcConnectionPool(
          mockService,
          mockSettings,
          acquireTimeout: const Duration(milliseconds: 30),
          metricsCollector: metrics,
        );

        when(
          () => mockService.connect(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: 'lease-1',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(() => mockService.disconnect('lease-1')).thenAnswer(
          (_) async => Failure(Exception('disconnect failed')),
        );

        final acquired = await pool.acquire('DSN=Test');
        expect(acquired.isSuccess(), isTrue);

        final released = await pool.release('lease-1');
        expect(released.isError(), isTrue);
        expect(metrics.poolReleaseFailureCount, 1);

        final activeAfter = await pool.getActiveCount();
        expect(activeAfter.getOrNull(), 1);

        final secondAcquire = await pool.acquire('DSN=Test');
        expect(secondAcquire.isError(), isTrue);
        verify(
          () => mockService.connect(
            any(),
            options: any(named: 'options'),
          ),
        ).called(1);
        verify(() => mockService.disconnect('lease-1')).called(1);
      },
    );

    test('discard should free the local lease even when disconnect fails', () async {
      mockSettings.poolSize = 1;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(milliseconds: 30),
        metricsCollector: metrics,
      );

      var connectCount = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectCount++;
        return Success(
          Connection(
            id: 'lease-$connectCount',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect('lease-1')).thenAnswer(
        (_) async => Failure(Exception('disconnect failed')),
      );
      when(() => mockService.disconnect('lease-2')).thenAnswer(
        (_) async => const Success(unit),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.getOrNull(), 'lease-1');

      final discarded = await pool.discard('lease-1');
      expect(discarded.isError(), isTrue);
      expect(metrics.poolReleaseFailureCount, 1);

      final activeAfterDiscard = await pool.getActiveCount();
      expect(activeAfterDiscard.getOrNull(), 0);

      final reacquired = await pool.acquire('DSN=Test');
      expect(reacquired.getOrNull(), 'lease-2');
      verify(() => mockService.disconnect('lease-1')).called(1);
    });

    test('release should free the local lease when disconnect throws a timeout', () async {
      mockSettings.poolSize = 1;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(milliseconds: 30),
        metricsCollector: metrics,
      );

      var connectCount = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectCount++;
        return Success(
          Connection(
            id: 'lease-$connectCount',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect('lease-1')).thenThrow(
        TimeoutException('Worker did not respond within 30s'),
      );
      when(() => mockService.disconnect('lease-2')).thenAnswer(
        (_) async => const Success(unit),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.getOrNull(), 'lease-1');

      final released = await pool.release('lease-1');
      expect(released.isError(), isTrue);
      expect(metrics.poolReleaseFailureCount, 1);

      final activeAfterRelease = await pool.getActiveCount();
      expect(activeAfterRelease.getOrNull(), 0);

      final reacquired = await pool.acquire('DSN=Test');
      expect(reacquired.getOrNull(), 'lease-2');
    });

    test('discard should free the local lease before disconnect completes', () async {
      mockSettings.poolSize = 1;
      pool = OdbcConnectionPool(
        mockService,
        mockSettings,
        acquireTimeout: const Duration(milliseconds: 30),
      );

      var connectCount = 0;
      final disconnectCompleter = Completer<Result<void>>();
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectCount++;
        return Success(
          Connection(
            id: 'lease-$connectCount',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect('lease-1')).thenAnswer(
        (_) => disconnectCompleter.future,
      );
      when(() => mockService.disconnect('lease-2')).thenAnswer(
        (_) async => const Success(unit),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.getOrNull(), 'lease-1');

      final discardFuture = pool.discard('lease-1');

      final activeAfterDiscardStarted = await pool.getActiveCount();
      expect(activeAfterDiscardStarted.getOrNull(), 0);

      final reacquired = await pool.acquire('DSN=Test');
      expect(reacquired.getOrNull(), 'lease-2');

      disconnectCompleter.complete(const Success(unit));
      final discarded = await discardFuture;
      expect(discarded.isSuccess(), isTrue);
    });

    test('release treats invalid connection id as a successful cleanup', () async {
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => mockService.disconnect('lease-1')).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'Invalid connection ID: 1000000'),
        ),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.isSuccess(), isTrue);

      final released = await pool.release('lease-1');
      expect(released.isSuccess(), isTrue);
      expect(metrics.poolReleaseFailureCount, 0);

      final activeAfter = await pool.getActiveCount();
      expect(activeAfter.getOrNull(), 0);
      verify(() => mockService.disconnect('lease-1')).called(1);
    });

    test('recycle should surface release failures and keep failing leases tracked', () async {
      var connectionCounter = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        connectionCounter++;
        return Success(
          Connection(
            id: 'lease-$connectionCounter',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect('lease-1')).thenAnswer(
        (_) async => const Success(unit),
      );
      when(() => mockService.disconnect('lease-2')).thenAnswer(
        (_) async => Failure(Exception('disconnect failed')),
      );

      await pool.acquire('DSN=Test');
      await pool.acquire('DSN=Test');

      final recycled = await pool.recycle('DSN=Test');
      expect(recycled.isError(), isTrue);
      expect(metrics.poolRecycleFailureCount, 1);

      final activeAfterRecycle = await pool.getActiveCount();
      expect(activeAfterRecycle.getOrNull(), 1);
      verify(() => mockService.disconnect('lease-1')).called(1);
      verify(() => mockService.disconnect('lease-2')).called(1);
    });

    test('warmUp should discard warmed connections and return success', () async {
      var counter = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        counter++;
        return Success(
          Connection(
            id: 'warm-$counter',
            connectionString: 'DSN=Warm',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final result = await pool.warmUp('DSN=Warm', warmUpCount: 2);

      expect(result.isSuccess(), isTrue);
      verify(() => mockService.disconnect('warm-1')).called(1);
      verify(() => mockService.disconnect('warm-2')).called(1);
      final activeAfter = await pool.getActiveCount();
      expect(activeAfter.getOrNull(), 0);
    });

    test('warmUp should surface cleanup failures instead of losing capacity silently', () async {
      var counter = 0;
      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        counter++;
        return Success(
          Connection(
            id: 'warm-$counter',
            connectionString: 'DSN=Warm',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => mockService.disconnect('warm-1')).thenAnswer(
        (_) async => Failure(Exception('cleanup failed')),
      );

      final result = await pool.warmUp('DSN=Warm', warmUpCount: 1);

      expect(result.isError(), isTrue);
      final activeAfter = await pool.getActiveCount();
      expect(activeAfter.getOrNull(), 0);
    });

    test('getHealthDiagnostics exposes strategy and circuit fields', () {
      final diagnostics = pool.getHealthDiagnostics();

      expect(diagnostics['strategy'], 'lease');
      expect(diagnostics['effective_strategy'], 'lease');
      expect(diagnostics['native_circuit_open'], isFalse);
      expect(diagnostics['native_skip_reason'], isNull);
    });
  });
}
