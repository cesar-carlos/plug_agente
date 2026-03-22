import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('OdbcNativeConnectionPool', () {
    late MockOdbcService mockService;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcNativeConnectionPool pool;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      pool = OdbcNativeConnectionPool(mockService, mockSettings);
    });

    test(
      'should create native pool once under concurrent acquire calls',
      () async {
        var createdPools = 0;
        var connectionCounter = 0;

        when(
          () => mockService.poolCreate(any(), any()),
        ).thenAnswer((_) async {
          createdPools++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const Success(77);
        });

        when(
          () => mockService.poolGetConnection(77),
        ).thenAnswer((_) async {
          connectionCounter++;
          return Success(
            Connection(
              id: 'conn-$connectionCounter',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });

        final results = await Future.wait(
          List.generate(12, (_) => pool.acquire('DSN=Test')),
        );

        expect(results.every((r) => r.isSuccess()), isTrue);
        expect(createdPools, 1);
        verify(() => mockService.poolCreate('DSN=Test', any())).called(1);
        verify(() => mockService.poolGetConnection(77)).called(12);
      },
    );

    test('should fail acquire when poolGetConnection times out', () async {
      mockSettings.loginTimeoutSeconds = 1;

      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(9));
      when(
        () => mockService.poolGetConnection(9),
      ).thenAnswer((_) => Completer<Result<Connection>>().future);

      final result = await pool.acquire('DSN=Test');
      expect(result.isError(), isTrue);
    });

    test('should close created pools and clear internal state', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(3));
      when(
        () => mockService.poolGetConnection(3),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'conn-1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(3),
      ).thenAnswer((_) async => const Success(unit));

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.isSuccess(), isTrue);

      final closed = await pool.closeAll();
      expect(closed.isSuccess(), isTrue);

      verify(() => mockService.poolClose(3)).called(1);
    });

    test(
      'should fail acquire when maxConnectionPools distinct strings are reached',
      () async {
        var nextPoolId = 0;
        when(
          () => mockService.poolCreate(any(), any()),
        ).thenAnswer((inv) async {
          nextPoolId++;
          return Success(nextPoolId);
        });
        when(
          () => mockService.poolGetConnection(any()),
        ).thenAnswer(
          (inv) async {
            final poolId = inv.positionalArguments[0] as int;
            return Success(
              Connection(
                id: 'conn-$poolId',
                connectionString: 'DSN',
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          },
        );

        for (var i = 0; i < ConnectionConstants.maxConnectionPools; i++) {
          final r = await pool.acquire('DSN=$i');
          expect(r.isSuccess(), isTrue, reason: 'pool $i');
        }

        final overflow = await pool.acquire('DSN=overflow');
        expect(overflow.isError(), isTrue);
      },
    );

    test('should fail acquire when poolCreate fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => Failure(Exception('pool create failed')));

      final result = await pool.acquire('DSN=Test');
      expect(result.isError(), isTrue);
      verify(() => mockService.poolCreate('DSN=Test', any())).called(1);
      verifyNever(() => mockService.poolGetConnection(any()));
    });

    test('should fail acquire when poolGetConnection fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(42));
      when(
        () => mockService.poolGetConnection(42),
      ).thenAnswer((_) async => Failure(Exception('no connection')));

      final result = await pool.acquire('DSN=Test');
      expect(result.isError(), isTrue);
    });

    test('should return Failure when poolReleaseConnection fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(5));
      when(
        () => mockService.poolGetConnection(5),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'to-release',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolReleaseConnection('to-release'),
      ).thenAnswer((_) async => Failure(Exception('release failed')));

      await pool.acquire('DSN=Test');
      final released = await pool.release('to-release');

      expect(released.isError(), isTrue);
    });

    test('should return Failure from closeAll when poolClose fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(8));
      when(
        () => mockService.poolGetConnection(8),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(8),
      ).thenAnswer((_) async => Failure(Exception('close failed')));

      await pool.acquire('DSN=Test');
      final closed = await pool.closeAll();

      expect(closed.isError(), isTrue);
    });

    test('recycle should close pool for connection string', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(11));
      when(
        () => mockService.poolGetConnection(11),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Recycle',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(11),
      ).thenAnswer((_) async => const Success(unit));

      await pool.acquire('DSN=Recycle');
      final recycled = await pool.recycle('DSN=Recycle');

      expect(recycled.isSuccess(), isTrue);
      verify(() => mockService.poolClose(11)).called(1);
    });

    test('recycle should return Failure when poolClose fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(12));
      when(
        () => mockService.poolGetConnection(12),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=X',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(12),
      ).thenAnswer((_) async => Failure(Exception('recycle close failed')));

      await pool.acquire('DSN=X');
      final recycled = await pool.recycle('DSN=X');

      expect(recycled.isError(), isTrue);
    });

    test('getActiveCount should sum active connections from pool state', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(20));
      when(
        () => mockService.poolGetConnection(20),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => mockService.poolGetState(20)).thenAnswer(
        (_) async => const Success(PoolState(size: 6, idle: 2)),
      );

      await pool.acquire('DSN=Test');
      final count = await pool.getActiveCount();

      expect(count.getOrNull(), 4);
    });

    test('healthCheckAll should fail when pool is unhealthy', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(30));
      when(
        () => mockService.poolGetConnection(30),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolHealthCheck(30),
      ).thenAnswer((_) async => const Success(false));

      await pool.acquire('DSN=Test');
      final health = await pool.healthCheckAll();

      expect(health.isError(), isTrue);
    });

    test('healthCheckAll should fail when poolHealthCheck errors', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(31));
      when(
        () => mockService.poolGetConnection(31),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolHealthCheck(31),
      ).thenAnswer((_) async => Failure(Exception('check failed')));

      await pool.acquire('DSN=Test');
      final health = await pool.healthCheckAll();

      expect(health.isError(), isTrue);
    });

    test('healthCheckAll should succeed when all pools healthy', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(40));
      when(
        () => mockService.poolGetConnection(40),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c1',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolHealthCheck(40),
      ).thenAnswer((_) async => const Success(true));

      await pool.acquire('DSN=Test');
      final health = await pool.healthCheckAll();

      expect(health.isSuccess(), isTrue);
    });
  });
}
