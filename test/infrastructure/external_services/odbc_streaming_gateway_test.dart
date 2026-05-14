import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('OdbcStreamingGateway', () {
    late MockOdbcService mockService;
    late MockOdbcConnectionSettings mockSettings;
    late MetricsCollector metrics;
    late OdbcStreamingGateway gateway;

    setUp(() {
      mockService = MockOdbcService();
      mockSettings = MockOdbcConnectionSettings();
      metrics = MetricsCollector()..clear();
      gateway = OdbcStreamingGateway(
        mockService,
        mockSettings,
        metricsCollector: metrics,
        cancelDisconnectTimeout: const Duration(milliseconds: 20),
      );
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
      expect(metrics.streamCancelRequestCount, 1);
      verify(
        () => mockService.disconnect('conn-cancel'),
      ).called(greaterThan(0));
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
          (_) async {
            unawaited(
              gateway.cancelActiveStream(
                reason: StreamingCancelReason.playgroundRowCap,
              ),
            );
          },
          fetchSize: 10,
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
        controller.add(
          const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [2],
              ],
              rowCount: 1,
            ),
          ),
        );
        await controller.close();

        final result = await execution;

        expect(result.isSuccess(), isTrue);
        expect(metrics.streamCancelRequestCount, 1);
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
        expect(metrics.streamCancelRequestCount, 1);
        verify(
          () => mockService.disconnect('conn-disconnect'),
        ).called(greaterThan(0));
      },
    );

    test(
      'cancel disconnect failure keeps direct connection lease reserved '
      'until execution unwinds',
      () async {
        final controller = StreamController<Result<QueryResult>>();
        mockSettings.poolSize = 1;
        final limiter = DirectOdbcConnectionLimiter(
          maxConcurrent: 1,
          acquireTimeout: const Duration(milliseconds: 30),
          metricsCollector: metrics,
        );
        gateway = OdbcStreamingGateway(
          mockService,
          mockSettings,
          directConnectionLimiter: limiter,
          metricsCollector: metrics,
          cancelDisconnectTimeout: const Duration(milliseconds: 20),
        );

        var connectionCounter = 0;
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
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
        when(() => mockService.initialize()).thenAnswer(
          (_) async => const Success(unit),
        );
        when(
          () => mockService.streamQuery('conn-1', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.streamQuery('conn-2', any()),
        ).thenAnswer(
          (_) => Stream<Result<QueryResult>>.fromIterable([
            const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [2],
                ],
                rowCount: 1,
              ),
            ),
          ]),
        );
        when(
          () => mockService.disconnect('conn-1'),
        ).thenAnswer((_) async => Failure(Exception('disconnect failed')));
        when(
          () => mockService.disconnect('conn-2'),
        ).thenAnswer((_) async => const Success(unit));

        final firstExecution = gateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          (_) async {},
        );

        await Future<void>.delayed(Duration.zero);
        expect(gateway.hasActiveStream, isTrue);

        final cancelResult = await gateway.cancelActiveStream();
        expect(cancelResult.isSuccess(), isTrue);
        expect(metrics.streamCancelDisconnectFailureCount, 1);

        final secondBeforeUnwind = await gateway.executeQueryStream(
          'SELECT 2',
          'DSN=Test',
          (_) async {},
        );
        expect(secondBeforeUnwind.isError(), isTrue);
        expect(secondBeforeUnwind.exceptionOrNull(), isA<domain.ConnectionFailure>());
        expect(connectionCounter, 1);

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

        final firstResult = await firstExecution;
        expect(firstResult.isError(), isTrue);

        final secondAfterUnwind = await gateway.executeQueryStream(
          'SELECT 2',
          'DSN=Test',
          (_) async {},
        );
        expect(secondAfterUnwind.isSuccess(), isTrue);
        expect(connectionCounter, 2);
      },
    );

    test(
      'should return success when cancel disconnect times out '
      '(metrics still record disconnect timeout)',
      () async {
        final controller = StreamController<Result<QueryResult>>();

        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'conn-cancel-timeout',
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
          () => mockService.streamQuery('conn-cancel-timeout', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.disconnect('conn-cancel-timeout'),
        ).thenAnswer((_) => Completer<Result<void>>().future);

        final execution = gateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          (_) async {},
        );

        await Future<void>.delayed(Duration.zero);
        final cancelResult = await gateway.cancelActiveStream();
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
        final executionResult = await execution;

        expect(cancelResult.isSuccess(), isTrue);
        expect(executionResult.isError(), isTrue);
        expect(metrics.streamCancelDisconnectTimeoutCount, 1);
      },
    );

    test(
      'cancel disconnect treats invalid connection id as successful cleanup',
      () async {
        final controller = StreamController<Result<QueryResult>>();

        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: 'conn-invalid-id',
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
          () => mockService.streamQuery('conn-invalid-id', any()),
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockService.disconnect('conn-invalid-id'),
        ).thenAnswer(
          (_) async => const Failure(
            ConnectionError(message: 'Invalid connection ID: 1000000'),
          ),
        );

        final execution = gateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          (_) async {},
        );

        await Future<void>.delayed(Duration.zero);
        final cancelResult = await gateway.cancelActiveStream();
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
        final executionResult = await execution;

        expect(cancelResult.isSuccess(), isTrue);
        expect(executionResult.isError(), isTrue);
        expect(metrics.streamCancelDisconnectFailureCount, 0);
      },
    );

    test('should keep structured ODBC error for streaming failures', () async {
      final controller = StreamController<Result<QueryResult>>();

      when(
        () => mockService.connect(any(), options: any(named: 'options')),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'conn-error',
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
        () => mockService.streamQuery('conn-error', any()),
      ).thenAnswer((_) => controller.stream);
      when(
        () => mockService.disconnect(any()),
      ).thenAnswer((_) async => const Success(unit));

      final execution = gateway.executeQueryStream(
        'SELECT * FROM users',
        'DSN=Test',
        (_) async {},
      );

      controller.add(const Failure(ConnectionError(message: 'network lost')));
      await controller.close();

      final result = await execution;

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.cause, isA<ConnectionError>());
    });
  });
}
