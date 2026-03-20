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
  });
}
