import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

void main() {
  group('MetricsCollector', () {
    late MetricsCollector collector;

    setUp(() {
      collector = MetricsCollector();
      collector.clear();
    });

    tearDown(() {
      collector.clear();
    });

    group('recordSuccess', () {
      test('should record successful metric', () {
        // Act
        collector.recordSuccess(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 10,
          columnCount: 5,
        );

        // Assert
        expect(collector.count, 1);
        expect(collector.metrics.length, 1);

        final metric = collector.metrics.first;
        expect(metric.queryId, 'query-1');
        expect(metric.query, 'SELECT * FROM users');
        expect(metric.executionDuration.inMilliseconds, 100);
        expect(metric.rowsAffected, 10);
        expect(metric.columnCount, 5);
        expect(metric.success, isTrue);
        expect(metric.errorMessage, isNull);
      });

      test('should emit metric on stream', () async {
        // Arrange
        final metrics = <QueryMetrics>[];
        collector.metricsStream.listen(metrics.add);

        // Act
        collector.recordSuccess(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 10,
          columnCount: 5,
        );

        // Wait for stream emission
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(metrics.length, 1);
        expect(metrics.first.success, isTrue);
      });
    });

    group('recordFailure', () {
      test('should record failure metric', () {
        // Act
        collector.recordFailure(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Table not found',
        );

        // Assert
        expect(collector.count, 1);

        final metric = collector.metrics.first;
        expect(metric.queryId, 'query-1');
        expect(metric.success, isFalse);
        expect(metric.errorMessage, 'Table not found');
        expect(metric.rowsAffected, 0);
        expect(metric.columnCount, 0);
      });

      test('should emit failure on stream', () async {
        // Arrange
        final metrics = <QueryMetrics>[];
        collector.metricsStream.listen(metrics.add);

        // Act
        collector.recordFailure(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Table not found',
        );

        // Wait for stream emission
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(metrics.length, 1);
        expect(metrics.first.success, isFalse);
      });
    });

    group('getSummary', () {
      test('should return empty summary when no metrics', () {
        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 0);
        expect(summary.successfulQueries, 0);
        expect(summary.failedQueries, 0);
        expect(summary.successRate, 0.0);
      });

      test('should calculate summary correctly', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 200),
          rowsAffected: 2,
          columnCount: 1,
        );
        collector.recordFailure(
          queryId: 'q3',
          query: 'SELECT 3',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 3);
        expect(summary.successfulQueries, 2);
        expect(summary.failedQueries, 1);
        expect(summary.successRate, 66.66666666666666);
        expect(
          summary.averageExecutionTime.inMilliseconds,
          116,
        ); // (100+200+50)/3
        expect(summary.totalRowsAffected, 3); // 1+2+0
      });

      test('should limit summary to recent metrics', () {
        // Arrange
        for (var i = 0; i < 150; i++) {
          collector.recordSuccess(
            queryId: 'q$i',
            query: 'SELECT $i',
            executionDuration: const Duration(milliseconds: 100),
            rowsAffected: 1,
            columnCount: 1,
          );
        }

        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 100); // Limited to 100
      });
    });

    group('getMetrics', () {
      test('should return all metrics when no filter', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordFailure(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final metrics = collector.getMetrics();

        // Assert
        expect(metrics.length, 2);
      });

      test('should filter by success', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        collector.recordFailure(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final successMetrics = collector.getMetrics(success: true);
        final failureMetrics = collector.getMetrics(success: false);

        // Assert
        expect(successMetrics.length, 1);
        expect(failureMetrics.length, 1);
        expect(successMetrics.first.success, isTrue);
        expect(failureMetrics.first.success, isFalse);
      });
    });

    group('getSlowQueries', () {
      test('should return queries above threshold', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 500),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 1500),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q3',
          query: 'SELECT 3',
          executionDuration: const Duration(milliseconds: 2000),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        final slowQueries = collector.getSlowQueries();

        // Assert
        expect(slowQueries.length, 2); // 1500ms and 2000ms
        expect(
          slowQueries.first.executionDuration.inMilliseconds,
          2000,
        ); // Sorted desc
      });

      test('should return empty list when no slow queries', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        final slowQueries = collector.getSlowQueries();

        // Assert
        expect(slowQueries, isEmpty);
      });
    });

    group('clear', () {
      test('should remove all metrics', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        collector.clear();

        // Assert
        expect(collector.count, 0);
        expect(collector.metrics, isEmpty);
      });

      test('should reset event counters', () {
        collector.recordTimeoutCancelSuccess();
        collector.recordTimeoutCancelFailure();
        collector.recordTransactionRollbackFailure();
        collector.recordIdempotencyFingerprintMismatch();
        collector.recordStreamCancelRequest();
        collector.recordStreamCancelBackpressure();
        collector.recordStreamCancelDisconnectFailure();
        collector.recordStreamCancelDisconnectTimeout();

        collector.clear();

        expect(collector.timeoutCancelSuccessCount, 0);
        expect(collector.timeoutCancelFailureCount, 0);
        expect(collector.transactionRollbackFailureCount, 0);
        expect(collector.idempotencyFingerprintMismatchCount, 0);
        expect(collector.authDecisionCacheHitCount, 0);
        expect(collector.authPolicyCacheMissCount, 0);
        expect(collector.rpcSqlExecuteStreamingChunksResponseCount, 0);
        expect(collector.rpcSqlExecuteStreamingFromDbResponseCount, 0);
        expect(collector.rpcSqlExecuteMaterializedResponseCount, 0);
        expect(collector.streamCancelRequestCount, 0);
        expect(collector.streamCancelBackpressureCount, 0);
        expect(collector.streamCancelDisconnectFailureCount, 0);
        expect(collector.streamCancelDisconnectTimeoutCount, 0);
      });
    });

    group('event counters', () {
      test('should increment timeout cancellation counters', () {
        collector.recordTimeoutCancelSuccess();
        collector.recordTimeoutCancelSuccess();
        collector.recordTimeoutCancelFailure();

        expect(collector.timeoutCancelSuccessCount, 2);
        expect(collector.timeoutCancelFailureCount, 1);
      });

      test('should increment streaming cancellation counters', () {
        collector.recordStreamCancelRequest();
        collector.recordStreamCancelRequest();
        collector.recordStreamCancelBackpressure();
        collector.recordStreamCancelDisconnectFailure();
        collector.recordStreamCancelDisconnectTimeout();

        expect(collector.streamCancelRequestCount, 2);
        expect(collector.streamCancelBackpressureCount, 1);
        expect(collector.streamCancelDisconnectFailureCount, 1);
        expect(collector.streamCancelDisconnectTimeoutCount, 1);
      });

      test('should increment rollback and idempotency mismatch counters', () {
        collector.recordTransactionRollbackFailure();
        collector.recordIdempotencyFingerprintMismatch();
        collector.recordIdempotencyFingerprintMismatch();

        expect(collector.transactionRollbackFailureCount, 1);
        expect(collector.idempotencyFingerprintMismatchCount, 2);
      });

      test('should increment auth cache counters', () {
        collector.recordAuthDecisionCacheHit();
        collector.recordAuthDecisionCacheMiss();
        collector.recordAuthPolicyCacheHit();
        collector.recordAuthPolicyCacheMiss();
        collector.recordAuthPolicyCacheMiss();

        expect(collector.authDecisionCacheHitCount, 1);
        expect(collector.authDecisionCacheMissCount, 1);
        expect(collector.authPolicyCacheHitCount, 1);
        expect(collector.authPolicyCacheMissCount, 2);
      });

      test('should increment rpc sql.execute path counters', () {
        collector.recordRpcSqlExecuteStreamingChunksResponse();
        collector.recordRpcSqlExecuteStreamingFromDbResponse();
        collector.recordRpcSqlExecuteMaterializedResponse();
        collector.recordRpcSqlExecuteMaterializedResponse();

        expect(collector.rpcSqlExecuteStreamingChunksResponseCount, 1);
        expect(collector.rpcSqlExecuteStreamingFromDbResponseCount, 1);
        expect(collector.rpcSqlExecuteMaterializedResponseCount, 2);
      });

      test('should expose streaming path and worker hold metrics in snapshot', () {
        collector.recordStreamingBatchedPath();
        collector.recordStreamingSingleChunkPath();
        collector.recordStreamingWorkerHoldTime(const Duration(milliseconds: 120));
        collector.recordStreamingWorkerHoldTime(const Duration(milliseconds: 200));

        final snapshot = collector.getSnapshot();

        expect(collector.streamingBatchedPathCount, 1);
        expect(collector.streamingSingleChunkPathCount, 1);
        expect(snapshot['streaming_batched_path'], 1);
        expect(snapshot['streaming_single_chunk_path'], 1);
        expect(snapshot['streaming_worker_hold_avg_time_ms'], 160.0);
        expect(snapshot['streaming_worker_hold_p95_time_ms'], 200);
        expect(snapshot['streaming_worker_hold_sample_count'], 2);
      });

      test('should expose numeric SQL queue counters and wait times in snapshot', () {
        collector.recordQueueRejection();
        collector.recordQueueRejection();
        collector.recordQueueTimeout();
        collector.recordQueueAdded(3);
        collector.recordWorkerStarted(2);
        collector.recordQueueWaitTime(const Duration(milliseconds: 10));
        collector.recordQueueWaitTime(const Duration(milliseconds: 30));
        collector.recordPoolWaitTime(const Duration(milliseconds: 5));
        collector.recordPoolWaitTime(const Duration(milliseconds: 15));
        collector.recordConnectTime(const Duration(milliseconds: 20));
        collector.recordSqlExecutionTime(const Duration(milliseconds: 40));
        collector.recordPreparedPrepareTime(const Duration(milliseconds: 8));

        final snapshot = collector.getSnapshot();

        expect(snapshot['sql_queue_rejection_count'], 2);
        expect(snapshot['sql_queue_timeout_count'], 1);
        expect(snapshot['sql_queue_current_size'], 3);
        expect(snapshot['sql_queue_max_size'], 3);
        expect(snapshot['sql_queue_current_workers'], 2);
        expect(snapshot['sql_queue_max_workers'], 2);
        expect(snapshot['sql_queue_avg_wait_time_ms'], 20.0);
        expect(snapshot['sql_queue_p95_wait_time_ms'], 30);
        expect(snapshot['sql_queue_max_recent_wait_time_ms'], 30);
        expect(snapshot['pool_wait_avg_time_ms'], 10.0);
        expect(snapshot['pool_wait_p95_time_ms'], 15);
        expect(snapshot['connect_avg_time_ms'], 20.0);
        expect(snapshot['sql_execution_avg_time_ms'], 40.0);
        expect(snapshot['prepared_prepare_avg_time_ms'], 8.0);
      });

      test('should increment auto-update counters', () {
        collector.recordAutoUpdateManualCheckStarted();
        collector.recordAutoUpdateManualCheckSuccessAvailable();
        collector.recordAutoUpdateManualCheckSuccessNotAvailable();
        collector.recordAutoUpdateManualCheckUpdaterError();
        collector.recordAutoUpdateManualCheckTriggerTimeout();
        collector.recordAutoUpdateManualCheckCompletionTimeout();
        collector.recordAutoUpdateManualCheckTriggerFailure();
        collector.recordAutoUpdateManualCheckNotInitialized();
        collector.recordAutoUpdateCircuitOpened();
        collector.recordAutoUpdateCircuitOpenRejected();

        expect(collector.autoUpdateManualCheckStartedCount, 1);
        expect(collector.autoUpdateManualCheckSuccessAvailableCount, 1);
        expect(collector.autoUpdateManualCheckSuccessNotAvailableCount, 1);
        expect(collector.autoUpdateManualCheckUpdaterErrorCount, 1);
        expect(collector.autoUpdateManualCheckTriggerTimeoutCount, 1);
        expect(collector.autoUpdateManualCheckCompletionTimeoutCount, 1);
        expect(collector.autoUpdateManualCheckTriggerFailureCount, 1);
        expect(collector.autoUpdateManualCheckNotInitializedCount, 1);
        expect(collector.autoUpdateCircuitOpenedCount, 1);
        expect(collector.autoUpdateCircuitOpenRejectedCount, 1);
      });

      test('should increment auto-update preference counters', () {
        collector.recordAutoUpdateNotificationsPreferenceEnabled();
        collector.recordAutoUpdateNotificationsPreferenceDisabled();
        collector.recordAutoUpdateAutomaticSilentPreferenceEnabled();
        collector.recordAutoUpdateAutomaticSilentPreferenceDisabled();
        collector.recordAutoUpdateManualOnlyModeApplied();

        final snapshot = collector.getSnapshot();
        expect(snapshot['auto_update_notifications_preference_enabled'], 1);
        expect(snapshot['auto_update_notifications_preference_disabled'], 1);
        expect(snapshot['auto_update_automatic_silent_preference_enabled'], 1);
        expect(snapshot['auto_update_automatic_silent_preference_disabled'], 1);
        expect(snapshot['auto_update_manual_only_mode_applied'], 1);
      });
    });

    group('recordRpcAgentActionBatchReadLimitRejected', () {
      test('should increment batch read limit rejected counter', () {
        collector.recordRpcAgentActionBatchReadLimitRejected();
        collector.recordRpcAgentActionBatchReadLimitRejected();

        expect(
          collector.getSnapshot()['rpc_remote_agent_action_batch_read_limit_rejected'],
          2,
        );
      });
    });

    group('recordRpcAgentActionRemoteOutcome', () {
      test('should increment bounded counters for published methods only', () {
        collector.recordRpcAgentActionRemoteOutcome('agent.action.run', success: true);
        collector.recordRpcAgentActionRemoteOutcome('agent.action.run', success: false);
        collector.recordRpcAgentActionRemoteOutcome('agent.action.validateRun', success: true);
        collector.recordRpcAgentActionRemoteOutcome('unknown.method', success: true);

        final snapshot = collector.getSnapshot();
        expect(snapshot['rpc_remote_agent_action_run_success'], 1);
        expect(snapshot['rpc_remote_agent_action_run_error'], 1);
        expect(snapshot['rpc_remote_agent_action_validate_run_success'], 1);
        expect(snapshot.containsKey('rpc_remote_agent_action_validate_run_error'), isFalse);
      });
    });

    group('exportToJson', () {
      test('should export metrics as JSON', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 5,
          columnCount: 2,
        );

        // Act
        final json = collector.exportToJson();

        // Assert
        expect(json.length, 1);
        expect(json.first['queryId'], 'q1');
        expect(json.first['query'], 'SELECT 1');
        expect(json.first['executionDurationMs'], 100);
        expect(json.first['rowsAffected'], 5);
        expect(json.first['columnCount'], 2);
        expect(json.first['success'], isTrue);
      });
    });

    group('ring buffer cap', () {
      test('should keep the most recent _maxMetrics entries and evict oldest first', () {
        // Arrange: push more than the cap (10000) so the buffer wraps.
        const cap = 10000;
        for (var i = 0; i < cap + 5; i++) {
          collector.recordSuccess(
            queryId: 'q$i',
            query: 'SELECT $i',
            executionDuration: const Duration(milliseconds: 1),
            rowsAffected: 0,
            columnCount: 0,
          );
        }

        // Assert: length is capped and the oldest entries were evicted.
        final metrics = collector.metrics;
        expect(metrics.length, cap);
        expect(metrics.first.queryId, 'q5');
        expect(metrics.last.queryId, 'q${cap + 4}');
      });
    });
  });
}
