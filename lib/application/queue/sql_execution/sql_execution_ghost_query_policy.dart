import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/queue/sql_execution/sql_execution_abort_port.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_backpressure.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_queue_saturation.dart';
import 'package:plug_agente/application/queue/sql_execution/sql_execution_queued_request.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';

final class SqlExecutionGhostQueryPolicy {
  const SqlExecutionGhostQueryPolicy({
    required ISqlInFlightExecutionAbortPort? inFlightAbortPort,
    required SqlExecutionQueueMetricsCollector? metricsCollector,
    required SqlExecutionQueueSaturationTracker saturationTracker,
    required int maxQueueSize,
    required int maxConcurrentWorkers,
  }) : _inFlightAbortPort = inFlightAbortPort,
       _metricsCollector = metricsCollector,
       _saturationTracker = saturationTracker,
       _maxQueueSize = maxQueueSize,
       _maxConcurrentWorkers = maxConcurrentWorkers;

  final ISqlInFlightExecutionAbortPort? _inFlightAbortPort;
  final SqlExecutionQueueMetricsCollector? _metricsCollector;
  final SqlExecutionQueueSaturationTracker _saturationTracker;
  final int _maxQueueSize;
  final int _maxConcurrentWorkers;

  domain.QueryExecutionFailure completeQueueWaitTimeout<T extends Object>({
    required SqlExecutionQueuedRequest<T> request,
    required Duration timeout,
    required TimeoutException error,
    required String? requestId,
    required int Function() queueSize,
    required int Function() activeWorkers,
    required bool Function(SqlExecutionQueuedRequest<Object> request) removeQueuedRequest,
  }) {
    request.isCancelled = true;
    request.cooperativeCancellationToken?.cancel();

    if (!request.hasStarted) {
      removeQueuedRequest(request);
      _metricsCollector?.recordQueueSizeChanged(queueSize());
      _saturationTracker.recordIfNeeded(
        queuedCount: queueSize(),
        maxQueueSize: _maxQueueSize,
        metricsCollector: _metricsCollector,
      );
    } else {
      _metricsCollector?.recordQueueTimeoutAfterWorkerStarted();
      final abortTargetId = SqlExecutionAbortPort.resolveAbortTargetId(
        requestId: requestId,
        request: request,
      );
      if (abortTargetId != null) {
        unawaited(_inFlightAbortPort?.abortInFlightExecution(abortTargetId));
      }
      developer.log(
        'SQL request queue wait timed out after worker started; native ODBC abort requested when in-flight handle is registered',
        name: 'sql_execution_queue',
        level: 900,
        error: {
          'request_id': requestId,
          'timeout_seconds': timeout.inSeconds,
          'queue_size': queueSize(),
          'active_workers': activeWorkers(),
          'ghost_query_risk': true,
          'cooperative_cancel_signalled': request.cooperativeCancellationToken?.isCancelled ?? false,
          'native_abort_requested': abortTargetId != null,
        },
      );
    }

    _metricsCollector?.recordQueueTimeout();
    developer.log(
      'SQL request TIMEOUT in queue',
      name: 'sql_execution_queue',
      level: 900,
      error: {
        'request_id': requestId,
        'timeout_seconds': timeout.inSeconds,
        'queue_size': queueSize(),
        'active_workers': activeWorkers(),
        'worker_started': request.hasStarted,
        'error': error,
      },
    );

    return domain.QueryExecutionFailure.withContext(
      message: 'SQL request timed out waiting in queue',
      cause: error,
      context: {
        ...SqlExecutionBackpressure.queueContext(
          reason: SqlPipelineContextConstants.queueWaitTimeoutReason,
          requestId: requestId,
          queueSize: queueSize(),
          maxQueueSize: _maxQueueSize,
          activeWorkers: activeWorkers(),
          maxWorkers: _maxConcurrentWorkers,
          userMessage: 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
        ),
        'timeout': true,
        'timeout_stage': 'queue',
        'timeout_seconds': timeout.inSeconds,
        'worker_started': request.hasStarted,
        if (request.hasStarted) 'ghost_query_risk': true,
      },
    );
  }
}
