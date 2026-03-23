import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
  });

  group('OdbcStreamingGateway', () {
    late MockOdbcService mockService;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcStreamingGateway gateway;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      gateway = OdbcStreamingGateway(mockService, mockSettings);
    });

    test(
      'should use default login timeout in connect options when setting is 0',
      () async {
        mockSettings.loginTimeoutSeconds = 0;
        when(() => mockService.initialize()).thenAnswer(
          (_) async => const Success(unit),
        );
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'conn-login',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          ),
        );
        final controller = StreamController<Result<QueryResult>>();
        when(
          () => mockService.streamQuery('conn-login', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.disconnect('conn-login'),
        ).thenAnswer((_) async => const Success(unit));

        final done = gateway.executeQueryStream(
          'SELECT 1',
          'DSN=Test',
          (_) async {},
        );
        await controller.close();
        await done;

        final verification = verify(
          () => mockService.connect(
            'DSN=Test',
            options: captureAny(named: 'options'),
          ),
        );
        verification.called(1);
        final options = verification.captured.single as ConnectionOptions;
        expect(options.loginTimeout, ConnectionConstants.defaultLoginTimeout);
      },
    );

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
      when(() => mockService.initialize()).thenAnswer(
        (_) async => const Success(unit),
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
        (c) async => receivedChunks.add(c),
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
      when(() => mockService.initialize()).thenAnswer(
        (_) async => const Success(unit),
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
        (chunk) async {
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
      verify(
        () => mockService.disconnect('conn-cancel'),
      ).called(1);
    });

    test(
      'should return success when cancelled for playground row cap',
      () async {
        final controller = StreamController<Result<QueryResult>>();

        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'conn-cap',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          ),
        );
        when(() => mockService.initialize()).thenAnswer(
          (_) async => const Success(unit),
        );
        when(
          () => mockService.streamQuery('conn-cap', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.disconnect(any()),
        ).thenAnswer((_) async => const Success(unit));

        final execution = gateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          (_) async {},
          fetchSize: 10,
        );

        unawaited(
          gateway.cancelActiveStream(
            reason: StreamingCancelReason.playgroundRowCap,
          ),
        );

        controller.add(
          const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );
        await controller.close();

        final result = await execution;

        expect(result.isSuccess(), isTrue);
      },
    );

    test(
      'should return failure when cancelled for socket disconnect',
      () async {
        final controller = StreamController<Result<QueryResult>>();

        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'conn-disconnect',
              connectionString: 'DSN=Test',
              createdAt: DateTime.now(),
              isActive: true,
            ),
          ),
        );
        when(() => mockService.initialize()).thenAnswer(
          (_) async => const Success(unit),
        );
        when(
          () => mockService.streamQuery('conn-disconnect', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.disconnect(any()),
        ).thenAnswer((_) async => const Success(unit));

        final execution = gateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          (chunk) async {
            if (chunk.isNotEmpty) {
              unawaited(
                gateway.cancelActiveStream(
                  reason: StreamingCancelReason.socketDisconnect,
                ),
              );
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
        verify(
          () => mockService.disconnect('conn-disconnect'),
        ).called(1);
      },
    );
  });
}
