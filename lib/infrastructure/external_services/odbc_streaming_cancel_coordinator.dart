import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart' as app_log;
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_active_connection.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Coordinates streaming cancel requests, disconnect timeouts, and failure mapping.
final class OdbcStreamingCancelCoordinator {
  OdbcStreamingCancelCoordinator({
    required OdbcService service,
    MetricsCollector? metricsCollector,
    Duration cancelDisconnectTimeout = const Duration(seconds: 8),
  }) : _service = service,
       _metrics = metricsCollector,
       _cancelDisconnectTimeout = cancelDisconnectTimeout;

  final OdbcService _service;
  final MetricsCollector? _metrics;
  final Duration _cancelDisconnectTimeout;

  Future<Result<void>> cancelActiveStreams({
    required Iterable<OdbcStreamingActiveConnection> streams,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    if (streams.isEmpty) {
      return const Success(unit);
    }

    for (final stream in streams) {
      _metrics?.recordStreamCancelRequest();
      if (reason == StreamingCancelReason.backpressureOverflow) {
        _metrics?.recordStreamCancelBackpressure();
      }
      stream.cancelReason = reason;
      stream.isCancelRequested = true;
      final result = await disconnectActiveStream(stream);
      if (result.isError()) {
        app_log.AppLogger.warning(
          'cancelActiveStream: disconnect after cancel request completed with error '
          '(cancellation was still applied; execution will stop): '
          '${result.exceptionOrNull()}',
        );
      }
    }

    return const Success(unit);
  }

  Future<void> safeDisconnect(String connectionId) async {
    try {
      await _service.disconnect(connectionId).timeout(_cancelDisconnectTimeout);
    } on TimeoutException {
      _metrics?.recordStreamCancelDisconnectTimeout();
    } on Object {
      // Best-effort cleanup path; caller already decided to abort.
    }
  }

  Future<Result<void>> disconnectActiveStream(
    OdbcStreamingActiveConnection stream,
  ) async {
    if (stream.isDisconnectStarted) {
      return const Success(unit);
    }

    stream.isDisconnectStarted = true;
    try {
      final result = await _service.disconnect(stream.connectionId).timeout(_cancelDisconnectTimeout);
      return result.fold(
        (_) => const Success(unit),
        (error) {
          if (OdbcErrorInspector.isInvalidConnectionId(error)) {
            return const Success(unit);
          }
          _metrics?.recordStreamCancelDisconnectFailure();
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'cancel_streaming_disconnect',
              context: {
                'reason': OdbcContextConstants.streamCancelDisconnectFailedReason,
                'executionId': stream.executionId,
                'user_message':
                    'A consulta foi marcada para cancelamento, mas a desconexão '
                    'do streaming não foi confirmada imediatamente.',
              },
            ),
          );
        },
      );
    } on TimeoutException catch (error) {
      _metrics?.recordStreamCancelDisconnectTimeout();
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'cancel_streaming_disconnect',
          context: {
            'reason': OdbcContextConstants.streamCancelDisconnectTimeoutReason,
            'executionId': stream.executionId,
            'timeout_ms': _cancelDisconnectTimeout.inMilliseconds,
            'user_message':
                'A consulta foi marcada para cancelamento, mas a desconexão '
                'do streaming não foi confirmada dentro do tempo esperado.',
          },
        ),
      );
    }
  }

  domain.Failure streamCancelledFailure({
    required String? executionId,
    required String? connectionId,
    required StreamingCancelReason reason,
  }) {
    final context = <String, dynamic>{
      ...?(connectionId == null ? null : <String, dynamic>{'connectionId': connectionId}),
      ...?(executionId == null ? null : <String, dynamic>{'executionId': executionId}),
      'reason': reason == StreamingCancelReason.socketDisconnect
          ? OdbcContextConstants.socketDisconnectReason
          : OdbcContextConstants.executionCancelledReason,
    };
    return OdbcFailureMapper.mapStreamingError(
      StateError('stream_cancelled_${reason.name}'),
      operation: 'executeQueryStream',
      context: context,
      cancelledByUser: reason != StreamingCancelReason.socketDisconnect,
    );
  }

  Future<Result<void>?> handleStreamingChunkCancellation({
    required OdbcStreamingActiveConnection activeStream,
    required String connectionId,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
  }) async {
    if ((cancellationToken?.isCancelled ?? false) && !activeStream.isCancelRequested) {
      activeStream.isCancelRequested = true;
      activeStream.cancelReason = cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect;
    }
    if (!activeStream.isCancelRequested) {
      return null;
    }
    if (activeStream.cancelReason == StreamingCancelReason.playgroundRowCap) {
      return const Success(unit);
    }
    if (activeStream.cancelReason == StreamingCancelReason.backpressureOverflow) {
      _metrics?.recordStreamCancelBackpressure();
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          StateError('stream_cancelled_backpressure_overflow'),
          operation: 'executeQueryStream',
          context: {
            'connectionId': connectionId,
            'rpc_error_code': RpcErrorCode.resultTooLarge,
            'reason': RpcStreamingConstants.backpressureOverflowReason,
          },
        ),
      );
    }
    if (activeStream.cancelReason == StreamingCancelReason.socketDisconnect) {
      app_log.AppLogger.info(
        'resilience: stream_cancelled_on_disconnect connection_id=$connectionId',
      );
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          StateError('stream_cancelled_on_disconnect'),
          operation: 'executeQueryStream',
          context: {
            'connectionId': connectionId,
            'reason': OdbcContextConstants.socketDisconnectReason,
          },
        ),
      );
    }
    return Failure(
      OdbcFailureMapper.mapStreamingError(
        StateError('stream_cancelled'),
        operation: 'executeQueryStream',
        context: {'connectionId': connectionId},
        cancelledByUser: true,
      ),
    );
  }
}
