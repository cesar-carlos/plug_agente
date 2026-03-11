import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('OdbcStreamingGateway', () {
    late MockOdbcService mockService;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcStreamingGateway gateway;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      gateway = OdbcStreamingGateway(mockService, mockSettings);
    });

    test('should split streamed rows by fetchSize', () async {
      final controller = StreamController<Result<QueryResult>>();
      final receivedChunks = <List<Map<String, dynamic>>>[];

      when(
        () => mockService.connect(any(), options: any(named: 'options')),
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
        () => mockService.streamQuery('conn-1', any()),
      ).thenAnswer((_) => controller.stream);
      when(
        () => mockService.disconnect('conn-1'),
      ).thenAnswer((_) async => const Success(unit));

      final execution = gateway.executeQueryStream(
        'SELECT * FROM users',
        'DSN=Test',
        receivedChunks.add,
        fetchSize: 2,
      );

      controller.add(
        const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
              [2],
              [3],
            ],
            rowCount: 3,
          ),
        ),
      );
      await controller.close();

      final result = await execution;

      expect(result.isSuccess(), isTrue);
      expect(receivedChunks.length, 2);
      expect(receivedChunks[0].length, 2);
      expect(receivedChunks[1].length, 1);
    });

    test('should cancel active streaming and stop with failure', () async {
      final controller = StreamController<Result<QueryResult>>();
      final receivedChunks = <List<Map<String, dynamic>>>[];

      when(
        () => mockService.connect(any(), options: any(named: 'options')),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'conn-cancel',
            connectionString: 'DSN=Test',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => mockService.streamQuery('conn-cancel', any()),
      ).thenAnswer((_) => controller.stream);
      when(
        () => mockService.disconnect(any()),
      ).thenAnswer((_) async => const Success(unit));

      final execution = gateway.executeQueryStream(
        'SELECT * FROM users',
        'DSN=Test',
        (chunk) {
          receivedChunks.add(chunk);
          if (receivedChunks.length == 1) {
            unawaited(gateway.cancelActiveStream());
          }
        },
        fetchSize: 2,
      );

      controller.add(
        const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
              [2],
            ],
            rowCount: 2,
          ),
        ),
      );

      // Second event makes the loop check cancellation and abort.
      controller.add(
        const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [3],
            ],
            rowCount: 1,
          ),
        ),
      );
      await controller.close();

      final result = await execution;

      expect(result.isError(), isTrue);
      verify(() => mockService.disconnect('conn-cancel')).called(greaterThan(0));
    });
  });
}
