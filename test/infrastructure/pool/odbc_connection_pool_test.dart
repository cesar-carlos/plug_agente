import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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

    test('release should succeed even when disconnect fails', () async {
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
        (_) async => Failure(Exception('disconnect failed')),
      );

      final acquired = await pool.acquire('DSN=Test');
      expect(acquired.isSuccess(), isTrue);

      final released = await pool.release('lease-1');
      expect(released.isSuccess(), isTrue);

      final activeAfter = await pool.getActiveCount();
      expect(activeAfter.getOrNull(), 0);
      verify(() => mockService.disconnect('lease-1')).called(1);
    });
  });
}
