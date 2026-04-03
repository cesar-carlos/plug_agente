import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
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

    test('should return failure when poolCreate fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'pool_create_failed'),
        ),
      );

      final result = await pool.acquire('DSN=Bad');

      expect(result.isError(), isTrue);
      verify(() => mockService.poolCreate('DSN=Bad', any())).called(1);
      verifyNever(() => mockService.poolGetConnection(any()));
    });

    test('should return failure when poolGetConnection fails', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(9));
      when(
        () => mockService.poolGetConnection(9),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'no_conn'),
        ),
      );

      final result = await pool.acquire('DSN=Test');

      expect(result.isError(), isTrue);
      verify(() => mockService.poolGetConnection(9)).called(1);
    });

    test('should map poolReleaseConnection failure', () async {
      when(
        () => mockService.poolReleaseConnection('cid'),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'release_failed'),
        ),
      );

      final result = await pool.release('cid');

      expect(result.isError(), isTrue);
      verify(() => mockService.poolReleaseConnection('cid')).called(1);
    });

    test('recycle with unknown connection string succeeds without close', () async {
      final result = await pool.recycle('DSN=Unknown');
      expect(result.isSuccess(), isTrue);
      verifyNever(() => mockService.poolClose(any()));
    });

    test('recycle maps poolClose failure', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(5));
      when(
        () => mockService.poolGetConnection(5),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c5',
            connectionString: 'DSN=Recycle',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(5),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'close_failed'),
        ),
      );

      await pool.acquire('DSN=Recycle');
      final result = await pool.recycle('DSN=Recycle');

      expect(result.isError(), isTrue);
      verify(() => mockService.poolClose(5)).called(1);
    });

    test('closeAll aggregates poolClose errors', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(11));
      when(
        () => mockService.poolGetConnection(11),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c11',
            connectionString: 'DSN=Multi',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolClose(11),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'boom'),
        ),
      );

      await pool.acquire('DSN=Multi');
      final closed = await pool.closeAll();

      expect(closed.isError(), isTrue);
    });

    test('getActiveCount sums active connections from pool state', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(21));
      when(
        () => mockService.poolGetConnection(21),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c21',
            connectionString: 'DSN=State',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => mockService.poolGetState(21)).thenAnswer(
        (_) async => const Success(
          PoolState(size: 10, idle: 4),
        ),
      );

      await pool.acquire('DSN=State');
      final count = await pool.getActiveCount();

      expect(count.isSuccess(), isTrue);
      expect(count.getOrThrow(), 6);
    });

    test('healthCheckAll fails when pool reports unhealthy', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(31));
      when(
        () => mockService.poolGetConnection(31),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c31',
            connectionString: 'DSN=Health',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolHealthCheck(31),
      ).thenAnswer((_) async => const Success(false));

      await pool.acquire('DSN=Health');
      final health = await pool.healthCheckAll();

      expect(health.isError(), isTrue);
    });

    test('healthCheckAll fails when healthCheck returns error', () async {
      when(
        () => mockService.poolCreate(any(), any()),
      ).thenAnswer((_) async => const Success(41));
      when(
        () => mockService.poolGetConnection(41),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c41',
            connectionString: 'DSN=HealthErr',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.poolHealthCheck(41),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'hc_failed'),
        ),
      );

      await pool.acquire('DSN=HealthErr');
      final health = await pool.healthCheckAll();

      expect(health.isError(), isTrue);
    });
  });
}
