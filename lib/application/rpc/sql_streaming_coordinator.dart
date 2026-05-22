import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

class SqlStreamingCoordinator {
  SqlStreamingCoordinator({
    required IStreamingDatabaseGateway? gateway,
    IRpcDispatchMetricsCollector? metrics,
  }) : _gateway = gateway,
       _metrics = metrics;

  final IStreamingDatabaseGateway? _gateway;
  final IRpcDispatchMetricsCollector? _metrics;
  final Map<String, ActiveSqlStreamExecution> _activeByStreamId = <String, ActiveSqlStreamExecution>{};
  final Map<String, ActiveSqlStreamExecution> _activeByExecutionId = <String, ActiveSqlStreamExecution>{};
  final Map<String, ActiveSqlStreamExecution> _activeByRequestId = <String, ActiveSqlStreamExecution>{};

  ActiveSqlStreamExecution? get activeExecution {
    if (_activeByStreamId.isEmpty) {
      return null;
    }
    return _activeByStreamId.values.last;
  }

  int get activeCount => _activeByStreamId.length;

  ActiveSqlStreamExecution markStarted({
    required String streamId,
    required String executionId,
    required String? requestId,
  }) {
    final execution = ActiveSqlStreamExecution(
      streamId: streamId,
      executionId: executionId,
      requestId: requestId,
      cancellationToken: CancellationToken(),
    );
    _activeByStreamId[streamId] = execution;
    _activeByExecutionId[executionId] = execution;
    final normalizedRequestId = requestId?.trim();
    if (normalizedRequestId != null && normalizedRequestId.isNotEmpty) {
      _activeByRequestId[normalizedRequestId] = execution;
    }
    return execution;
  }

  void markFinished(ActiveSqlStreamExecution execution) {
    final current = _activeByStreamId[execution.streamId];
    if (current != execution) {
      return;
    }
    _activeByStreamId.remove(execution.streamId);
    _activeByExecutionId.remove(execution.executionId);
    final requestId = execution.requestId;
    if (requestId != null) {
      _activeByRequestId.remove(requestId);
    }
  }

  ActiveSqlStreamExecution? find({
    String? executionId,
    String? requestId,
  }) {
    final normalizedExecutionId = executionId?.trim();
    if (normalizedExecutionId != null && normalizedExecutionId.isNotEmpty) {
      final execution = _activeByExecutionId[normalizedExecutionId];
      if (execution != null) {
        return execution;
      }
    }

    final normalizedRequestId = requestId?.trim();
    if (normalizedRequestId != null && normalizedRequestId.isNotEmpty) {
      return _activeByRequestId[normalizedRequestId];
    }

    return null;
  }

  Future<Result<void>> cancel({
    required ActiveSqlStreamExecution execution,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    execution.cancel(reason);
    final gateway = _gateway;
    if (gateway == null) {
      return Failure(
        domain.NotFoundFailure.withContext(
          message: 'Active SQL stream not found',
          context: <String, Object?>{
            'execution_id': execution.executionId,
            'request_id': execution.requestId,
          },
        ),
      );
    }

    if (!gateway.hasActiveStream) {
      markFinished(execution);
      _metrics?.recordSqlStreamCancelled(reason.name);
      return const Success(unit);
    }

    final result = await gateway.cancelActiveStream(
      executionId: execution.executionId,
      reason: reason,
    );
    if (result.isSuccess()) {
      markFinished(execution);
      _metrics?.recordSqlStreamCancelled(reason.name);
    } else {
      _metrics?.recordSqlStreamCancelFailed(reason.name);
    }
    return result;
  }

  Future<void> cancelActiveStreamOnDisconnect() async {
    final gateway = _gateway;
    final activeExecutions = _activeByStreamId.values.toList(growable: false);
    if (activeExecutions.isEmpty) {
      if (gateway != null && gateway.hasActiveStream) {
        final result = await gateway.cancelActiveStream(
          reason: StreamingCancelReason.socketDisconnect,
        );
        if (result.isSuccess()) {
          _metrics?.recordSqlStreamCancelled(StreamingCancelReason.socketDisconnect.name);
        } else {
          _metrics?.recordSqlStreamCancelFailed(StreamingCancelReason.socketDisconnect.name);
        }
      }
      return;
    }
    for (final execution in activeExecutions) {
      execution.cancel(StreamingCancelReason.socketDisconnect);
    }

    if (gateway == null) {
      _clearActive();
      return;
    }

    if (!gateway.hasActiveStream) {
      _clearActive();
      _metrics?.recordSqlStreamCancelled(StreamingCancelReason.socketDisconnect.name);
      return;
    }

    final result = await gateway.cancelActiveStream(
      reason: StreamingCancelReason.socketDisconnect,
    );
    if (result.isSuccess()) {
      _clearActive();
      _metrics?.recordSqlStreamCancelled(StreamingCancelReason.socketDisconnect.name);
    } else {
      _metrics?.recordSqlStreamCancelFailed(StreamingCancelReason.socketDisconnect.name);
    }
  }

  void _clearActive() {
    _activeByStreamId.clear();
    _activeByExecutionId.clear();
    _activeByRequestId.clear();
  }
}

class ActiveSqlStreamExecution {
  ActiveSqlStreamExecution({
    required this.streamId,
    required this.executionId,
    required this.requestId,
    required this.cancellationToken,
  });

  final String streamId;
  final String executionId;
  final String? requestId;
  final CancellationToken cancellationToken;
  StreamingCancelReason? cancelReason;

  void cancel(StreamingCancelReason reason) {
    cancelReason = reason;
    cancellationToken.cancel();
  }
}
