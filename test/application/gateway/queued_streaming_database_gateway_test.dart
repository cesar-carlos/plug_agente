import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_streaming_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class _MockStreamingGateway extends Mock implements IStreamingDatabaseGateway {}

Future<void> _noopOnChunk(List<Map<String, dynamic>> chunk) async {}

void main() {
  setUpAll(() {
    registerFallbackValue(_noopOnChunk);
  });

  group('QueuedStreamingDatabaseGateway', () {
    test('should route streaming execution through the shared SQL queue', () async {
      final delegate = _MockStreamingGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedStreamingDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      when(() => delegate.hasActiveStream).thenReturn(false);
      var delegateInvoked = false;
      when(
        () => delegate.executeQueryStream(
          any(),
          any(),
          any(),
          fetchSize: any(named: 'fetchSize'),
          chunkSizeBytes: any(named: 'chunkSizeBytes'),
          executionId: any(named: 'executionId'),
          queryTimeout: any(named: 'queryTimeout'),
          cancellationToken: any(named: 'cancellationToken'),
          cancellationReasonProvider: any(named: 'cancellationReasonProvider'),
          onSetupComplete: any(named: 'onSetupComplete'),
        ),
      ).thenAnswer((_) async {
        delegateInvoked = true;
        return const Success(unit);
      });

      final result = await gateway.executeQueryStream(
        'SELECT 1',
        'DSN=test',
        (_) async {},
        executionId: 'stream-1',
      );

      expect(result.isSuccess(), isTrue);
      expect(delegateInvoked, isTrue);
      expect(queue.activeWorkers, 0);
    });

    test('should release queue worker after setup while stream body runs', () async {
      final delegate = _MockStreamingGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedStreamingDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );
      final streamBlocker = Completer<void>();
      var setupCompleteCalled = false;

      when(() => delegate.hasActiveStream).thenReturn(false);
      when(
        () => delegate.executeQueryStream(
          any(),
          any(),
          any(),
          fetchSize: any(named: 'fetchSize'),
          chunkSizeBytes: any(named: 'chunkSizeBytes'),
          executionId: any(named: 'executionId'),
          queryTimeout: any(named: 'queryTimeout'),
          cancellationToken: any(named: 'cancellationToken'),
          cancellationReasonProvider: any(named: 'cancellationReasonProvider'),
          onSetupComplete: any(named: 'onSetupComplete'),
        ),
      ).thenAnswer((invocation) async {
        final onSetup = invocation.namedArguments[#onSetupComplete] as void Function()?;
        onSetup?.call();
        setupCompleteCalled = true;
        await streamBlocker.future;
        return const Success(unit);
      });

      unawaited(
        gateway.executeQueryStream(
          'SELECT 1',
          'DSN=test',
          (_) async {},
          executionId: 'stream-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(setupCompleteCalled, isTrue);
      expect(queue.activeWorkers, 0);
      expect(queue.activeStreamingWorkers, 0);

      var secondTaskStarted = false;
      final secondFuture = queue.submit<String>(
        () async {
          secondTaskStarted = true;
          return const Success('query');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(secondTaskStarted, isTrue);

      streamBlocker.complete();
      await secondFuture;
      expect(queue.activeWorkers, 0);
    });

    test(
      'should signal cooperative cancel when streaming enqueue times out',
      () async {
        final delegate = _MockStreamingGateway();
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 1,
          defaultEnqueueTimeout: const Duration(milliseconds: 30),
        );
        final gateway = QueuedStreamingDatabaseGateway(
          delegate: delegate,
          queue: queue,
        );
        final firstBlocker = Completer<void>();
        final cooperativeToken = CancellationToken();

        when(() => delegate.hasActiveStream).thenReturn(false);
        var streamInvocation = 0;
        when(
          () => delegate.executeQueryStream(
            any(),
            any(),
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSizeBytes: any(named: 'chunkSizeBytes'),
            executionId: any(named: 'executionId'),
            queryTimeout: any(named: 'queryTimeout'),
            cancellationToken: any(named: 'cancellationToken'),
            cancellationReasonProvider: any(named: 'cancellationReasonProvider'),
            onSetupComplete: any(named: 'onSetupComplete'),
          ),
        ).thenAnswer((invocation) async {
          streamInvocation++;
          if (streamInvocation == 1) {
            await firstBlocker.future;
            return const Success(unit);
          }
          final onSetup = invocation.namedArguments[#onSetupComplete] as void Function()?;
          onSetup?.call();
          await Future<void>.delayed(const Duration(seconds: 1));
          return const Success(unit);
        });

        unawaited(
          gateway.executeQueryStream(
            'SELECT 1',
            'DSN=test',
            (_) async {},
            executionId: 'stream-blocker',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final result = await gateway.executeQueryStream(
          'SELECT 2',
          'DSN=test',
          (_) async {},
          executionId: 'stream-timeout',
          cancellationToken: cooperativeToken,
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        expect(cooperativeToken.isCancelled, isTrue);

        firstBlocker.complete();
      },
    );

    test(
      'should queue burst streaming setup under single streaming worker limit',
      () async {
        final delegate = _MockStreamingGateway();
        final queue = SqlExecutionQueue(
          maxQueueSize: 8,
          maxConcurrentWorkers: 2,
          maxConcurrentStreamingWorkers: 1,
        );
        final gateway = QueuedStreamingDatabaseGateway(
          delegate: delegate,
          queue: queue,
        );
        final setupOrder = <String>[];
        final setupBlockers = <String, Completer<void>>{
          for (final id in ['stream-a', 'stream-b', 'stream-c']) id: Completer<void>(),
        };
        final bodyBlockers = <String, Completer<void>>{
          for (final id in ['stream-a', 'stream-b', 'stream-c']) id: Completer<void>(),
        };

        when(() => delegate.hasActiveStream).thenReturn(false);
        when(
          () => delegate.executeQueryStream(
            any(),
            any(),
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSizeBytes: any(named: 'chunkSizeBytes'),
            executionId: any(named: 'executionId'),
            queryTimeout: any(named: 'queryTimeout'),
            cancellationToken: any(named: 'cancellationToken'),
            cancellationReasonProvider: any(named: 'cancellationReasonProvider'),
            onSetupComplete: any(named: 'onSetupComplete'),
          ),
        ).thenAnswer((invocation) async {
          final executionId = invocation.namedArguments[#executionId] as String? ?? 'unknown';
          await setupBlockers[executionId]!.future;
          setupOrder.add(executionId);
          final onSetup = invocation.namedArguments[#onSetupComplete] as void Function()?;
          onSetup?.call();
          await bodyBlockers[executionId]!.future;
          return const Success(unit);
        });

        final futures = <Future<Result<void>>>[
          gateway.executeQueryStream('SELECT 1', 'DSN=test', (_) async {}, executionId: 'stream-a'),
          gateway.executeQueryStream('SELECT 2', 'DSN=test', (_) async {}, executionId: 'stream-b'),
          gateway.executeQueryStream('SELECT 3', 'DSN=test', (_) async {}, executionId: 'stream-c'),
        ];
        await Future<void>.delayed(Duration.zero);

        expect(queue.activeStreamingWorkers, lessThanOrEqualTo(1));
        expect(setupOrder, isEmpty);

        setupBlockers['stream-a']!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(setupOrder, equals(<String>['stream-a']));
        expect(queue.activeStreamingWorkers, lessThanOrEqualTo(1));

        setupBlockers['stream-b']!.complete();
        await Future<void>.delayed(Duration.zero);
        expect(setupOrder, equals(<String>['stream-a', 'stream-b']));

        setupBlockers['stream-c']!.complete();
        for (final blocker in bodyBlockers.values) {
          blocker.complete();
        }
        await Future.wait(futures);

        expect(setupOrder, containsAllInOrder(<String>['stream-a', 'stream-b', 'stream-c']));
        expect(queue.activeStreamingWorkers, 0);
        expect(queue.activeWorkers, 0);
      },
    );
  });
}
