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
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_columnar_wire_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
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
    IOdbcBatchedStreamingQuerySource? batchedQuerySource,
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    MetricsCollector? metricsCollector,
    OdbcProfileRecommendedOptions? recommendedOptions,
    Duration cancelDisconnectTimeout = _defaultCancelDisconnectTimeout,
  }) : _batchedQuerySource = batchedQuerySource,
       _recommendedOptions = recommendedOptions,
       _directConnectionLimiter =
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
  final OdbcProfileRecommendedOptions? _recommendedOptions;
  final IOdbcBatchedStreamingQuerySource? _batchedQuerySource;
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
      'direct_limiter_by_operation_class': _directConnectionLimiter.getOperationClassDiagnostics(),
      // odbc_fast 4.x uses columnar batched streaming on the native path;
      // plug_agente infers batched usage when multiple native chunks are observed.
      'native_batched_path_observable': false,
      'native_path_inference': 'multi_chunk_implies_batched_columnar',
    };
  }

  bool _messageIndicatesInvalidConnectionId(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  ConnectionOptions _buildStreamingConnectionOptions(
    int chunkSizeBytes, {
    int? hintedBufferBytes,
    Duration? queryTimeout,
    int? maxResultBufferBytes,
    bool lazyStrings = false,
  }) {
    final normalizedChunkSize = max(chunkSizeBytes, 64 * 1024);
    final resolvedMaxResultBufferBytes =
        maxResultBufferBytes ??
        max(
          normalizedChunkSize,
          max(
            hintedBufferBytes ?? 0,
            OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024,
          ),
        );
    final initialResultBufferBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      resolvedMaxResultBufferBytes,
    );

    final plugAcquireOptions = ConnectionAcquireOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout ?? ConnectionConstants.defaultStreamingQueryTimeout,
      maxResultBufferBytes: resolvedMaxResultBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
    final recommended = _recommendedOptions?.connection;
    if (recommended != null) {
      return OdbcRecommendedOptionsMerger.mergeConnectionOptions(
        plugOptions: plugAcquireOptions,
        recommended: recommended,
        lazyStrings: lazyStrings,
      );
    }

    return ConnectionOptions(
      loginTimeout: plugAcquireOptions.loginTimeout,
      queryTimeout: plugAcquireOptions.queryTimeout,
      maxResultBufferBytes: plugAcquireOptions.maxResultBufferBytes,
      initialResultBufferBytes: plugAcquireOptions.initialResultBufferBytes,
      autoReconnectOnConnectionLost: plugAcquireOptions.autoReconnectOnConnectionLost ?? true,
      maxReconnectAttempts: plugAcquireOptions.maxReconnectAttempts,
      reconnectBackoff: plugAcquireOptions.reconnectBackoff,
      lazyStrings: lazyStrings,
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
    Future<void> Function(StreamingWireChunk chunk)? onWireChunk,
    void Function()? onSetupComplete,
    Map<String, dynamic>? parameters,
    bool columnarWireOnly = false,
  }) async {
    final emitColumnarWire = onWireChunk != null && isOdbcStreamColumnarWireEnabled();
    final skipRowMaterialization = emitColumnarWire && columnarWireOnly;
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
    final nativeStreamingOptions = OdbcStreamingNativeOptions.resolve(
      fetchSize: fetchSize,
      chunkSizeBytes: chunkSizeBytes,
      settingsMaxResultBufferMb: OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(
        _settings,
      ),
      hintedBufferBytes: hintedBufferBytes,
    );
    final streamingOptions = _buildStreamingConnectionOptions(
      nativeStreamingOptions.nativeChunkSizeBytes,
      hintedBufferBytes: hintedBufferBytes,
      queryTimeout: queryTimeout,
      maxResultBufferBytes: nativeStreamingOptions.maxResultBufferBytes,
      lazyStrings: connectionStringBenefitsFromLazyStrings(connectionString),
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
    onSetupComplete?.call();
    var nativeChunkCount = 0;
    final prefersRowMajorStreaming = connectionStringPrefersRowMajorStreaming(connectionString);
    try {
      if (prefersRowMajorStreaming) {
        final lazyStrings = connectionStringBenefitsFromLazyStrings(connectionString);
        final queryStream = _openRowMajorStreamingQueryStream(
          connectionId: connection.id,
          query: query,
          nativeStreamingOptions: nativeStreamingOptions,
          parameters: parameters,
          lazyStrings: lazyStrings,
        );
        await for (final chunkResult in queryStream) {
          nativeChunkCount++;
          final shouldStop = await _handleStreamingChunkCancellation(
            activeStream: activeStream,
            connectionId: connection.id,
            cancellationToken: cancellationToken,
            cancellationReasonProvider: cancellationReasonProvider,
          );
          if (shouldStop != null) {
            return shouldStop;
          }

          await chunkResult.fold(
            (queryResult) async {
              await emitMappedRowMajorChunks(
                columns: queryResult.columns,
                rows: queryResult.rows,
                fetchSize: nativeStreamingOptions.fetchSize,
                onChunk: onChunk,
                isCancelRequested: () => activeStream.isCancelRequested,
              );
            },
            (error) {
              throw error;
            },
          );
        }
      } else {
        final queryStream = _openColumnarStreamingQueryStream(
          connectionId: connection.id,
          query: query,
          nativeStreamingOptions: nativeStreamingOptions,
          parameters: parameters,
        );
        await for (final chunkResult in queryStream) {
          nativeChunkCount++;
          final shouldStop = await _handleStreamingChunkCancellation(
            activeStream: activeStream,
            connectionId: connection.id,
            cancellationToken: cancellationToken,
            cancellationReasonProvider: cancellationReasonProvider,
          );
          if (shouldStop != null) {
            return shouldStop;
          }

          await chunkResult.fold(
            (columnarResult) async {
              await OdbcColumnarStreamChunkEmitter.emit(
                result: columnarResult,
                fetchSize: nativeStreamingOptions.fetchSize,
                onChunk: onChunk,
                onWireChunk: emitColumnarWire ? onWireChunk : null,
                includeColumnarWire: emitColumnarWire,
                wireOnly: skipRowMaterialization,
                isCancelRequested: () => activeStream.isCancelRequested,
              );
            },
            (error) {
              throw error;
            },
          );
        }
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
      _recordNativeStreamingPathMetrics(nativeChunkCount);
      await _disconnectActiveStream(activeStream);
      activeStream.lease.release();
      _activeStreams.remove(streamExecutionId);
    }
  }

  @override
  Future<Result<void>> executeMultiResultQueryStream(
    String query,
    String connectionString,
    Future<void> Function(StreamingWireChunk chunk) onWireChunk, {
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
    void Function()? onSetupComplete,
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

    if (executionId != null && _activeStreams.containsKey(executionId)) {
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          StateError('stream_duplicate_execution_id'),
          operation: 'executeMultiResultQueryStream',
          context: {
            'executionId': executionId,
            'reason': OdbcContextConstants.streamDuplicateExecutionIdReason,
          },
        ),
      );
    }

    final desiredDirectConcurrency = ConnectionConstants.directOdbcConnectionConcurrency(_settings.poolSize);
    if (_directConnectionLimiter.maxConcurrent != desiredDirectConcurrency) {
      _directConnectionLimiter.reconfigureMaxConcurrent(desiredDirectConcurrency);
    }
    final leaseResult = await _directConnectionLimiter.acquire(
      operation: 'streaming_multi_result',
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
      ConnectionConstants.defaultStreamingChunkSizeKb * 1024,
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
            operation: 'connect_streaming_multi_result',
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
    final activeStream = _ActiveStreamingConnection(
      executionId: streamExecutionId,
      connectionId: connection.id,
      lease: directLease,
    );
    _activeStreams[streamExecutionId] = activeStream;
    onSetupComplete?.call();

    try {
      var resultSetIndex = 0;
      var itemIndex = 0;
      await for (final itemResult in _service.streamQueryMulti(connection.id, query)) {
        if ((cancellationToken?.isCancelled ?? false) && !activeStream.isCancelRequested) {
          activeStream.isCancelRequested = true;
          activeStream.cancelReason = cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect;
        }
        if (activeStream.isCancelRequested) {
          return Failure(
            _streamCancelledFailure(
              executionId: streamExecutionId,
              connectionId: connection.id,
              reason: activeStream.cancelReason,
            ),
          );
        }

        await itemResult.fold(
          (item) async {
            final currentItemIndex = itemIndex++;
            if (item.resultSet != null) {
              final rows = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(item.resultSet!);
              await onWireChunk(
                StreamingWireChunk(
                  rows: rows,
                  resultSetIndex: resultSetIndex,
                  multiResultItemIndex: currentItemIndex,
                ),
              );
              resultSetIndex++;
              return;
            }

            await onWireChunk(
              StreamingWireChunk(
                rows: const <Map<String, dynamic>>[],
                rowCountOnly: item.rowCount ?? 0,
                multiResultItemIndex: currentItemIndex,
              ),
            );
          },
          (error) {
            throw error;
          },
        );
      }

      return const Success(unit);
    } on Object catch (e) {
      return Failure(
        OdbcFailureMapper.mapStreamingError(
          e,
          operation: 'executeMultiResultQueryStream',
          context: {
            'connectionId': connection.id,
            'executionId': streamExecutionId,
          },
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

  void _recordNativeStreamingPathMetrics(int nativeChunkCount) {
    if (nativeChunkCount <= 0) {
      return;
    }
    if (nativeChunkCount > 1) {
      _metrics?.recordStreamingBatchedPath();
      return;
    }
    _metrics?.recordStreamingSingleChunkPath();
  }

  Stream<Result<TypedColumnarResult>> _openColumnarStreamingQueryStream({
    required String connectionId,
    required String query,
    required OdbcStreamingNativeOptions nativeStreamingOptions,
    Map<String, dynamic>? parameters,
  }) {
    if (parameters != null && parameters.isNotEmpty) {
      return _service
          .streamQueryNamed(connectionId, query, parameters)
          .map((result) => result.map(toTypedColumnar));
    }

    final batchedSource = _batchedQuerySource;
    if (batchedSource == null) {
      return _service.streamQueryColumnar(connectionId, query);
    }

    final nativeConnectionId = int.tryParse(connectionId);
    if (nativeConnectionId == null || nativeConnectionId <= 0) {
      return _service.streamQueryColumnar(connectionId, query);
    }

    return batchedSource.streamColumnarQuery(
      nativeConnectionId,
      query,
      nativeStreamingOptions,
    );
  }

  Stream<Result<QueryResult>> _openRowMajorStreamingQueryStream({
    required String connectionId,
    required String query,
    required OdbcStreamingNativeOptions nativeStreamingOptions,
    Map<String, dynamic>? parameters,
    bool lazyStrings = false,
  }) {
    if (parameters != null && parameters.isNotEmpty) {
      return _service.streamQueryNamed(connectionId, query, parameters);
    }

    final batchedSource = _batchedQuerySource;
    final nativeConnectionId = int.tryParse(connectionId);
    if (batchedSource != null && nativeConnectionId != null && nativeConnectionId > 0) {
      return batchedSource.streamRowMajorQuery(
        nativeConnectionId,
        query,
        nativeStreamingOptions,
        lazyStrings: lazyStrings,
      );
    }

    return _service.streamQuery(connectionId, query);
  }

  Future<Result<void>?> _handleStreamingChunkCancellation({
    required _ActiveStreamingConnection activeStream,
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
