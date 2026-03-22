import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
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
    late OdbcConnectionPool pool;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      pool = OdbcConnectionPool(mockService, mockSettings);
    });

    test('should wait for poolSize before opening another lease', () async {
      mockSettings.poolSize = 1;
      var leaseCounter = 0;

      when(
        () => mockService.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        leaseCounter++;
        return Success(
          Connection(
            id: 'lease-$leaseCounter',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });

      final first = await pool.acquire('DSN=Test');
      expect(first.getOrNull(), 'lease-1');

      when(() => mockService.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final secondFuture = pool.acquire('DSN=Test');
      await pumpEventQueue();
      expect(leaseCounter, 1);

      await pool.release('lease-1');

      final second = await secondFuture;
      expect(second.isSuccess(), isTrue);
      expect(second.getOrNull(), 'lease-2');
      expect(leaseCounter, 2);
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

    test(
      'should return Failure when connect fails and release lease for retry',
      () async {
        mockSettings.poolSize = 1;
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Failure(Exception('driver offline')),
        );

        final failed = await pool.acquire('DSN=Test');
        expect(failed.isError(), isTrue);

        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'lease-ok',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          ),
        );

        final ok = await pool.acquire('DSN=Test');
        expect(ok.isSuccess(), isTrue);
        expect(ok.getOrNull(), 'lease-ok');
      },
    );

    test('should return Failure when disconnect fails on release', () async {
      when(
        () => mockService.connect(any(), options: any(named: 'options')),
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
        (_) async => Failure(Exception('disconnect failed')),
      );

      await pool.acquire('DSN=Test');
      final released = await pool.release('lease-1');

      expect(released.isError(), isTrue);
      verify(() => mockService.disconnect('lease-1')).called(1);
    });

    test(
      'should return Failure from closeAll when any disconnect fails',
      () async {
        var n = 0;
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          n++;
          return Success(
            Connection(
              id: n == 1 ? 'bad-lease' : 'good-lease',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(() => mockService.disconnect(any())).thenAnswer((inv) async {
          final id = inv.positionalArguments.first as String;
          if (id == 'bad-lease') {
            return Failure(Exception('close failed'));
          }
          return const Success(unit);
        });

        await pool.acquire('DSN=Test');
        await pool.acquire('DSN=Test');

        final closed = await pool.closeAll();
        expect(closed.isError(), isTrue);
      },
    );

    test('closeAll should fail waiters blocked on lease limit', () async {
      mockSettings.poolSize = 1;
      var c = 0;
      when(
        () => mockService.connect(any(), options: any(named: 'options')),
      ).thenAnswer((_) async {
        c++;
        return Success(
          Connection(
            id: 'lease-$c',
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
      final second = pool.acquire('DSN=Test');
      await pumpEventQueue();

      final closed = await pool.closeAll();
      expect(closed.isSuccess(), isTrue);

      final secondResult = await second;
      expect(secondResult.isError(), isTrue);
    });

    test('recycle should disconnect all leases for that connection string', () async {
      mockSettings.poolSize = 4;
      var n = 0;
      when(
        () => mockService.connect(any(), options: any(named: 'options')),
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

      final recycled = await pool.recycle('DSN=Test');
      expect(recycled.isSuccess(), isTrue);
      verify(() => mockService.disconnect('id-1')).called(1);
      verify(() => mockService.disconnect('id-2')).called(1);

      final active = await pool.getActiveCount();
      expect(active.getOrNull(), 0);
    });

    test(
      'recycle should return Failure when disconnect fails but still free lease slots',
      () async {
        mockSettings.poolSize = 4;
        var n = 0;
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
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
        when(() => mockService.disconnect(any())).thenAnswer((inv) async {
          final id = inv.positionalArguments.first as String;
          if (id == 'id-1') {
            return Failure(Exception('disconnect failed'));
          }
          return const Success(unit);
        });

        await pool.acquire('DSN=Test');
        await pool.acquire('DSN=Test');

        final recycled = await pool.recycle('DSN=Test');
        expect(recycled.isError(), isTrue);

        when(() => mockService.disconnect(any())).thenAnswer(
          (_) async => const Success(unit),
        );
        final after = await pool.acquire('DSN=Test');
        expect(after.isSuccess(), isTrue);
      },
    );

    test('recycle should succeed when no leases exist for connection string', () async {
      final result = await pool.recycle('DSN=Unknown');
      expect(result.isSuccess(), isTrue);
      verifyNever(() => mockService.disconnect(any()));
    });

    test(
      'should use defaultPoolSize when poolSize is zero',
      () async {
        mockSettings.poolSize = 0;
        var connectCount = 0;
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          connectCount++;
          return Success(
            Connection(
              id: 'c-$connectCount',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(() => mockService.disconnect(any())).thenAnswer(
          (_) async => const Success(unit),
        );

        final firstBatch = List.generate(
          ConnectionConstants.defaultPoolSize,
          (_) => pool.acquire('DSN=Test'),
        );
        await Future.wait(firstBatch);
        expect(connectCount, ConnectionConstants.defaultPoolSize);

        final fifth = pool.acquire('DSN=Test');
        await pumpEventQueue();
        expect(connectCount, ConnectionConstants.defaultPoolSize);

        await pool.release('c-1');
        final fifthResult = await fifth;
        expect(fifthResult.isSuccess(), isTrue);
        expect(connectCount, ConnectionConstants.defaultPoolSize + 1);
      },
    );
  });
}
