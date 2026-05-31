import 'dart:async';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart' as app_log;
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

class _ActiveStreamingConnection {
  _ActiveStreamingConnection({
    required this.executionId,
    required this.connectionId,
    required this.lease,
  });

  final String executionId;
  final String connectionId;
  final DirectOdbcConnectionLease lease;
  bool isCancelRequested = false;
  bool isDisconnectStarted = false;
  StreamingCancelReason cancelReason = StreamingCancelReason.user;
}

/// Gateway com suporte a streaming real para grandes datasets.
///
/// Implementa streaming incremental usando streamQuery da odbc_fast,
/// processando resultados em chunks sem carregar tudo em memória.
class OdbcStreamingGateway implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics {
  OdbcStreamingGateway(
    this._service,
    this._settings, {
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    MetricsCollector? metricsCollector,
    Duration cancelDisconnectTimeout = _defaultCancelDisconnectTimeout,
  }) : _directConnectionLimiter =
           directConnectionLimiter ??
           DirectOdbcConnectionLimiter(
             maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
               _settings.poolSize,
             ),
             acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
             metricsCollector: metricsCollector,
           ),
       _metrics = metricsCollector,
       _cancelDisconnectTimeout = cancelDisconnectTimeout;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector? _metrics;
  final Duration _cancelDisconnectTimeout;
  final Map<String, _ActiveStreamingConnection> _activeStreams = <String, _ActiveStreamingConnection>{};
  final ConnectionCircuitBreakerCache _circuitBreakers = ConnectionCircuitBreakerCache(
    factory: () => ConnectionCircuitBreaker(
      failureThreshold: ConnectionConstants.circuitBreakerFailureThreshold,
      resetTimeout: ConnectionConstants.circuitBreakerResetTimeout,
    ),
  );
  bool _initialized = false;
  Future<Result<void>>? _initialization;
  static const Duration _defaultCancelDisconnectTimeout = Duration(seconds: 8);
  final OdbcAdaptiveBufferCache _adaptiveBufferCache = OdbcAdaptiveBufferCache();

  ConnectionCircuitBreaker _getCircuitBreaker(String connectionString) {
    return _circuitBreakers.getOrCreate(connectionString);
  }

  @override
  bool get hasActiveStream => _activeStreams.isNotEmpty;

  @override
  int get activeStreamCount => _activeStreams.length;

  @override
  Map<String, Object?> getStreamingDiagnostics() {
    return {
      'enabled': true,
      'active_streams': activeStreamCount,
      'direct_limiter_active_count': _directConnectionLimiter.activeCount,
      'direct_limiter_max_concurrent': _directConnectionLimiter.maxConcurrent,
      'direct_limiter_saturated': _directConnectionLimiter.isSaturated,
    };
  }

  bool _messageIndicatesInvalidConnectionId(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  ConnectionOptions _buildStreamingConnectionOptions(
    int chunkSizeBytes, {
    int? hintedBufferBytes,
    Duration? queryTimeout,
  }) {
    final normalizedChunkSize = max(chunkSizeBytes, 64 * 1024);
    final maxResultBufferBytes = max(
      normalizedChunkSize,
      max(
        hintedBufferBytes ?? 0,
        OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024,
      ),
    );
    final initialResultBufferBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      maxResultBufferBytes,
    );

    return ConnectionOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout ?? ConnectionConstants.defaultStreamingQueryTimeout,
      maxResultBufferBytes: maxResultBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }

  Future<Result<void>> _ensureInitialized() {
    if (_initialized) {
      return Future<Result<void>>.value(const Success(unit));
    }
    return _initialization ??= _initializeOnce();
  }

  Future<Result<void>> _initializeOnce() async {
    final initResult = await _service.initialize();
    return initResult.fold(
      (_) {
        _initialized = true;
        return const Success(unit);
      },
      (error) {
        _initialization = null;
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'initialize_streaming_odbc',
            context: {
              'reason': OdbcContextConstants.odbcInitializationFailedReason,
              'user_message': 'Não foi possível inicializar o ambiente ODBC para streaming.',
            },
          ),
        );
      },
    );
  }

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      final initFailure = initResult.exceptionOrNull();
      if (initFailure != null) {
        return Failure(initFailure);
      }
      return Failure(
        domain.ConnectionFailure('Falha desconhecida ao inicializar ODBC'),
      );
    }

    // Fail fast when the caller-provided executionId is already in use. The
    // late check below (after connect) still covers the case where the id is
    // derived from connection.id, but this short-circuit avoids spending a
    // lease + connect on a duplicate retry.
    if (executionId != null && _activeStreams.containsKey(executionId)) {
      app_log.AppLogger.warning(
        'executeQueryStream: duplicate executionId rejected before connect ($executionId)',
      );
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          StateError('stream_duplicate_execution_id'),
          operation: 'executeQueryStream',
          context: {
            'executionId': executionId,
            'reason': OdbcContextConstants.streamDuplicateExecutionIdReason,
            'user_message':
                'Já existe uma consulta de streaming em andamento com este identificador. '
                'Aguarde a finalização ou use um identificador diferente.',
          },
        ),
      );
    }

    // Conectar com opções otimizadas para streaming
    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: query,
    );
    final desiredDirectConcurrency = ConnectionConstants.directOdbcConnectionConcurrency(_settings.poolSize);
    if (_directConnectionLimiter.maxConcurrent != desiredDirectConcurrency) {
      _directConnectionLimiter.reconfigureMaxConcurrent(desiredDirectConcurrency);
    }
    final leaseResult = await _directConnectionLimiter.acquire(
      operation: 'streaming_query',
    );
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    if (cancellationToken?.isCancelled ?? false) {
      directLease.release();
      return Failure(
        _streamCancelledFailure(
          executionId: executionId,
          connectionId: null,
          reason: cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect,
        ),
      );
    }
    final streamingOptions = _buildStreamingConnectionOptions(
      chunkSizeBytes,
      hintedBufferBytes: hintedBufferBytes,
      queryTimeout: queryTimeout,
    );

    final circuitBreaker = _getCircuitBreaker(connectionString);
    final connResult = await circuitBreaker.execute<Connection>(
      connectionString,
      () async {
        final raw = await _service.connect(connectionString, options: streamingOptions);
        if (raw.isSuccess()) {
          return Success(raw.getOrThrow());
        }
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            raw.exceptionOrNull()!,
            operation: 'connect_streaming',
          ),
        );
      },
    );
    if (connResult.isError()) {
      directLease.release();
      return Failure(connResult.exceptionOrNull()!);
    }
    final connection = connResult.getOrThrow();

    final streamExecutionId = executionId ?? connection.id;
    if (cancellationToken?.isCancelled ?? false) {
      await _safeDisconnect(connection.id);
      directLease.release();
      return Failure(
        _streamCancelledFailure(
          executionId: streamExecutionId,
          connectionId: connection.id,
          reason: cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect,
        ),
      );
    }
    if (_activeStreams.containsKey(streamExecutionId)) {
      // Two concurrent streams sharing an executionId would let the first one
      // overwrite the second's tracking entry, breaking cancel routing and
      // causing the first to drop the second's lease on its finally block.
      // Reject the duplicate; callers must use unique IDs per execution.
      await _safeDisconnect(connection.id);
      directLease.release();
      app_log.AppLogger.warning(
        'executeQueryStream: duplicate executionId rejected ($streamExecutionId)',
      );
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          StateError('stream_duplicate_execution_id'),
          operation: 'executeQueryStream',
          context: {
            'executionId': streamExecutionId,
            'reason': OdbcContextConstants.streamDuplicateExecutionIdReason,
            'user_message':
                'Já existe uma consulta de streaming em andamento com este identificador. '
                'Aguarde a finalização ou use um identificador diferente.',
          },
        ),
      );
    }
    final activeStream = _ActiveStreamingConnection(
      executionId: streamExecutionId,
      connectionId: connection.id,
      lease: directLease,
    );
    _activeStreams[streamExecutionId] = activeStream;
    try {
      // Usar streaming real para processar chunks incrementalmente
      await for (final chunkResult in _service.streamQuery(
        connection.id,
        query,
      )) {
        if ((cancellationToken?.isCancelled ?? false) && !activeStream.isCancelRequested) {
          activeStream.isCancelRequested = true;
          activeStream.cancelReason = cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect;
        }
        if (activeStream.isCancelRequested) {
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
                  'connectionId': connection.id,
                  'rpc_error_code': RpcErrorCode.resultTooLarge,
                  'reason': RpcStreamingConstants.backpressureOverflowReason,
                },
              ),
            );
          }
          if (activeStream.cancelReason == StreamingCancelReason.socketDisconnect) {
            app_log.AppLogger.info(
              'resilience: stream_cancelled_on_disconnect connection_id=${connection.id}',
            );
            return Failure(
              OdbcFailureMapper.mapStreamingError(
                StateError('stream_cancelled_on_disconnect'),
                operation: 'executeQueryStream',
                context: {
                  'connectionId': connection.id,
                  'reason': OdbcContextConstants.socketDisconnectReason,
                },
              ),
            );
          }
          return Failure(
            OdbcFailureMapper.mapStreamingError(
              StateError('stream_cancelled'),
              operation: 'executeQueryStream',
              context: {'connectionId': connection.id},
              cancelledByUser: true,
            ),
          );
        }

        await chunkResult.fold(
          (queryResult) async {
            await _emitQueryResultRows(queryResult, fetchSize, onChunk, activeStream: activeStream);
          },
          (error) {
            throw error;
          },
        );
      }

      return const Success(unit);
    } on Object catch (e) {
      if (OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
        e.toString(),
      )) {
        _adaptiveBufferCache.rememberExpandedBuffer(
          connectionString: connectionString,
          sql: query,
          currentBufferBytes:
              streamingOptions.maxResultBufferBytes ??
              (OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024),
          errorMessage: e.toString(),
        );
      }
      final context = <String, dynamic>{
        'connectionId': connection.id,
        'executionId': streamExecutionId,
      };
      if (activeStream.cancelReason == StreamingCancelReason.backpressureOverflow) {
        context['rpc_error_code'] = RpcErrorCode.resultTooLarge;
        context['reason'] = RpcStreamingConstants.backpressureOverflowReason;
      }
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          e,
          operation: 'executeQueryStream',
          context: context,
        ),
      );
    } finally {
      await _disconnectActiveStream(activeStream);
      activeStream.lease.release();
      _activeStreams.remove(streamExecutionId);
    }
  }

  /// Resets the circuit breaker for a specific connection string.
  ///
  /// Useful after configuration changes or manual recovery.
  void resetCircuitBreaker(String connectionString) {
    _circuitBreakers.reset(connectionString);
  }

  /// Best-effort disconnect with a bounded timeout. Used on cleanup paths
  /// (early cancellation, duplicate executionId rejection) where we cannot
  /// afford to block forever waiting for the driver.
  Future<void> _safeDisconnect(String connectionId) async {
    try {
      await _service.disconnect(connectionId).timeout(_cancelDisconnectTimeout);
    } on TimeoutException {
      _metrics?.recordStreamCancelDisconnectTimeout();
    } on Object {
      // Swallow: caller has already decided to abort the stream; logging
      // happens in the disconnect path when the gateway is asked to cancel
      // an active stream via cancelActiveStream.
    }
  }

  domain.Failure _streamCancelledFailure({
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

  @override
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    final streams = executionId == null
        ? _activeStreams.values.toList(growable: false)
        : <_ActiveStreamingConnection>[?_activeStreams[executionId]];
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
      final result = await _disconnectActiveStream(stream);
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

  Future<Result<void>> _disconnectActiveStream(
    _ActiveStreamingConnection stream,
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
          if (_messageIndicatesInvalidConnectionId(error)) {
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

  Future<void> _emitQueryResultRows(
    QueryResult result,
    int fetchSize,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    _ActiveStreamingConnection? activeStream,
  }) async {
    final safeFetchSize = fetchSize > 0 ? fetchSize : 1000;
    final columns = result.columns;
    var chunk = <Map<String, dynamic>>[];

    for (final row in result.rows) {
      chunk.add(mapOdbcRowToStreamingMap(columns, row));
      if (chunk.length >= safeFetchSize) {
        await onChunk(chunk);
        chunk = <Map<String, dynamic>>[];
        // Yield between chunks so a large driver-delivered result does not
        // monopolize the UI isolate while it is being re-framed for Socket.IO.
        await Future<void>.delayed(Duration.zero);
        if (activeStream?.isCancelRequested ?? false) {
          return;
        }
      }
    }

    if (chunk.isNotEmpty && !(activeStream?.isCancelRequested ?? false)) {
      await onChunk(chunk);
    }
  }
}
