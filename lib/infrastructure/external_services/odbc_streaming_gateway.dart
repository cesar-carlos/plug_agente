import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart' as app_log;
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_columnar_wire_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_runtime_lifecycle.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_active_connection.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_cancel_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_connect_phase.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_connection_options_builder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_query_stream_opener.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

/// Gateway com suporte a streaming real para grandes datasets.
///
/// Implementa streaming incremental usando streamQuery da odbc_fast,
/// processando resultados em chunks sem carregar tudo em memória.
class OdbcStreamingGateway
    implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics, IOdbcConnectionCircuitBreaker {
  OdbcStreamingGateway(
    this._service,
    this._settings, {
    IOdbcBatchedStreamingQuerySource? batchedQuerySource,
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    MetricsCollector? metricsCollector,
    OdbcProfileRecommendedOptions? recommendedOptions,
    Duration cancelDisconnectTimeout = _defaultCancelDisconnectTimeout,
    OdbcInFlightExecutionRegistry? inFlightExecutionRegistry,
    OdbcStreamingConnectionOptionsBuilder? connectionOptionsBuilder,
    OdbcStreamingCancelCoordinator? cancelCoordinator,
    OdbcStreamingConnectPhase? connectPhase,
    OdbcStreamingQueryStreamOpener? queryStreamOpener,
    OdbcRuntimeLifecycle? runtimeLifecycle,
    OdbcStreamingSessionCache? streamingSessionCache,
  }) : _inFlightRegistry = inFlightExecutionRegistry,
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
       _connectionOptionsBuilder =
           connectionOptionsBuilder ??
           OdbcStreamingConnectionOptionsBuilder(
             settings: _settings,
             recommendedOptions: recommendedOptions,
           ),
       _cancelCoordinator =
           cancelCoordinator ??
           OdbcStreamingCancelCoordinator(
             service: _service,
             metricsCollector: metricsCollector,
             cancelDisconnectTimeout: cancelDisconnectTimeout,
           ),
       _connectPhase =
           connectPhase ??
           OdbcStreamingConnectPhase(
             service: _service,
             circuitBreakers: _sharedCircuitBreakerCache,
             directConnectionLimiter:
                 directConnectionLimiter ??
                 DirectOdbcConnectionLimiter(
                   maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
                     _settings.poolSize,
                   ),
                   acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
                   metricsCollector: metricsCollector,
                 ),
             sessionCache: streamingSessionCache,
           ),
       _queryStreamOpener =
           queryStreamOpener ??
           OdbcStreamingQueryStreamOpener(
             service: _service,
             batchedQuerySource: batchedQuerySource,
           ),
       _runtimeLifecycle = runtimeLifecycle ?? OdbcRuntimeLifecycle(_service);
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector? _metrics;
  final OdbcInFlightExecutionRegistry? _inFlightRegistry;
  final OdbcStreamingConnectionOptionsBuilder _connectionOptionsBuilder;
  final OdbcStreamingCancelCoordinator _cancelCoordinator;
  final OdbcStreamingConnectPhase _connectPhase;
  final OdbcStreamingQueryStreamOpener _queryStreamOpener;
  final OdbcRuntimeLifecycle _runtimeLifecycle;
  final Map<String, OdbcStreamingActiveConnection> _activeStreams = <String, OdbcStreamingActiveConnection>{};
  static final ConnectionCircuitBreakerCache _sharedCircuitBreakerCache = ConnectionCircuitBreakerCache(
    factory: () => ConnectionCircuitBreaker(
      failureThreshold: ConnectionConstants.circuitBreakerFailureThreshold,
      resetTimeout: ConnectionConstants.circuitBreakerResetTimeout,
    ),
  );
  final ConnectionCircuitBreakerCache _circuitBreakers = _sharedCircuitBreakerCache;
  static const Duration _defaultCancelDisconnectTimeout = Duration(seconds: 8);
  final OdbcAdaptiveBufferCache _adaptiveBufferCache = OdbcAdaptiveBufferCache();

  Future<Result<void>> _ensureInitialized() {
    return _runtimeLifecycle.ensureInitialized(
      operation: 'initialize_streaming_odbc',
      userMessage: 'Não foi possível inicializar o ambiente ODBC para streaming.',
    );
  }

  Future<void> invalidateAfterWorkerRecovery() async {
    if (_activeStreams.isNotEmpty) {
      final streams = _activeStreams.values.toList(growable: false);
      await _cancelCoordinator.cancelActiveStreams(streams: streams);
      _activeStreams.clear();
    }
    await _connectPhase.sessionCache.drainCachedSessions();
    _runtimeLifecycle.invalidateAfterWorkerRecovery();
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
      'native_batched_path_observable': false,
      'native_path_inference': 'multi_chunk_implies_batched_columnar',
    };
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

    if (executionId != null && _activeStreams.containsKey(executionId)) {
      app_log.AppLogger.warning(
        'executeQueryStream: duplicate executionId rejected before connect ($executionId)',
      );
      return Failure(
        _connectPhase.duplicateExecutionIdFailure(
          executionId: executionId,
          operation: 'executeQueryStream',
        ),
      );
    }

    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: query,
    );
    final desiredDirectConcurrency = ConnectionConstants.directOdbcConnectionConcurrency(_settings.poolSize);
    if (_directConnectionLimiter.maxConcurrent != desiredDirectConcurrency) {
      _directConnectionLimiter.reconfigureMaxConcurrent(desiredDirectConcurrency);
    }
    final leaseResult = await _connectPhase.acquireLease(operation: 'streaming_query');
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    if (cancellationToken?.isCancelled ?? false) {
      directLease.release();
      return Failure(
        _cancelCoordinator.streamCancelledFailure(
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
    final streamingOptions = _connectionOptionsBuilder.build(
      nativeStreamingOptions.nativeChunkSizeBytes,
      hintedBufferBytes: hintedBufferBytes,
      queryTimeout: queryTimeout,
      maxResultBufferBytes: nativeStreamingOptions.maxResultBufferBytes,
      lazyStrings: connectionStringBenefitsFromLazyStrings(connectionString),
    );

    final connResult = await _connectPhase.connectStreaming(
      connectionString: connectionString,
      options: streamingOptions,
      operation: 'connect_streaming',
    );
    if (connResult.isError()) {
      directLease.release();
      return Failure(connResult.exceptionOrNull()!);
    }
    final connection = connResult.getOrThrow();

    final streamExecutionId = executionId ?? connection.id;
    if (cancellationToken?.isCancelled ?? false) {
      await _cancelCoordinator.safeDisconnect(connection.id);
      directLease.release();
      return Failure(
        _cancelCoordinator.streamCancelledFailure(
          executionId: streamExecutionId,
          connectionId: connection.id,
          reason: cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect,
        ),
      );
    }
    if (_activeStreams.containsKey(streamExecutionId)) {
      await _cancelCoordinator.safeDisconnect(connection.id);
      directLease.release();
      return Failure(
        _connectPhase.duplicateExecutionIdFailure(
          executionId: streamExecutionId,
          operation: 'executeQueryStream',
          logWarning: true,
        ),
      );
    }
    final activeStream = OdbcStreamingActiveConnection(
      executionId: streamExecutionId,
      connectionId: connection.id,
      lease: directLease,
    );
    _activeStreams[streamExecutionId] = activeStream;
    _registerInFlightExecution(streamExecutionId, connection.id);
    onSetupComplete?.call();
    var nativeChunkCount = 0;
    var streamCompletedSuccessfully = false;
    final prefersRowMajorStreaming = connectionStringPrefersRowMajorStreaming(connectionString);
    try {
      if (prefersRowMajorStreaming) {
        final lazyStrings = connectionStringBenefitsFromLazyStrings(connectionString);
        final queryStream = _queryStreamOpener.openRowMajor(
          connectionId: connection.id,
          query: query,
          nativeStreamingOptions: nativeStreamingOptions,
          parameters: parameters,
          lazyStrings: lazyStrings,
        );
        await for (final chunkResult in queryStream) {
          nativeChunkCount++;
          final shouldStop = await _cancelCoordinator.handleStreamingChunkCancellation(
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
        final queryStream = _queryStreamOpener.openColumnar(
          connectionId: connection.id,
          query: query,
          nativeStreamingOptions: nativeStreamingOptions,
          parameters: parameters,
        );
        await for (final chunkResult in queryStream) {
          nativeChunkCount++;
          final shouldStop = await _cancelCoordinator.handleStreamingChunkCancellation(
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

      streamCompletedSuccessfully = true;
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
      await _releaseStreamingConnection(
        activeStream: activeStream,
        connectionString: connectionString,
        reuseEligible: streamCompletedSuccessfully,
      );
      activeStream.lease.release();
      _unregisterInFlightExecution(streamExecutionId);
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
        _connectPhase.duplicateExecutionIdFailure(
          executionId: executionId,
          operation: 'executeMultiResultQueryStream',
        ),
      );
    }

    final desiredDirectConcurrency = ConnectionConstants.directOdbcConnectionConcurrency(_settings.poolSize);
    if (_directConnectionLimiter.maxConcurrent != desiredDirectConcurrency) {
      _directConnectionLimiter.reconfigureMaxConcurrent(desiredDirectConcurrency);
    }
    final leaseResult = await _connectPhase.acquireLease(operation: 'streaming_multi_result');
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    if (cancellationToken?.isCancelled ?? false) {
      directLease.release();
      return Failure(
        _cancelCoordinator.streamCancelledFailure(
          executionId: executionId,
          connectionId: null,
          reason: cancellationReasonProvider?.call() ?? StreamingCancelReason.socketDisconnect,
        ),
      );
    }

    final streamingOptions = _connectionOptionsBuilder.build(
      ConnectionConstants.defaultStreamingChunkSizeKb * 1024,
      queryTimeout: queryTimeout,
    );
    final connResult = await _connectPhase.connectStreaming(
      connectionString: connectionString,
      options: streamingOptions,
      operation: 'connect_streaming_multi_result',
    );
    if (connResult.isError()) {
      directLease.release();
      return Failure(connResult.exceptionOrNull()!);
    }
    final connection = connResult.getOrThrow();
    final streamExecutionId = executionId ?? connection.id;
    final activeStream = OdbcStreamingActiveConnection(
      executionId: streamExecutionId,
      connectionId: connection.id,
      lease: directLease,
    );
    _activeStreams[streamExecutionId] = activeStream;
    _registerInFlightExecution(streamExecutionId, connection.id);
    onSetupComplete?.call();

    var streamCompletedSuccessfully = false;
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
            _cancelCoordinator.streamCancelledFailure(
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

      streamCompletedSuccessfully = true;
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
      await _releaseStreamingConnection(
        activeStream: activeStream,
        connectionString: connectionString,
        reuseEligible: streamCompletedSuccessfully,
      );
      activeStream.lease.release();
      _unregisterInFlightExecution(streamExecutionId);
      _activeStreams.remove(streamExecutionId);
    }
  }

  @override
  void resetCircuitBreaker(String connectionString) {
    _circuitBreakers.reset(connectionString);
  }

  @override
  void clearAllCircuitBreakers() {
    _circuitBreakers.clear();
  }

  @override
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    final streams = executionId == null
        ? _activeStreams.values.toList(growable: false)
        : <OdbcStreamingActiveConnection>[?_activeStreams[executionId]];
    return _cancelCoordinator.cancelActiveStreams(streams: streams, reason: reason);
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

  void _registerInFlightExecution(String requestId, String connectionId) {
    if (requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.register(
      requestId,
      OdbcInFlightExecutionHandle(connectionId: connectionId),
    );
  }

  void _unregisterInFlightExecution(String requestId) {
    if (requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.unregister(requestId);
  }

  Future<void> _releaseStreamingConnection({
    required OdbcStreamingActiveConnection activeStream,
    required String connectionString,
    required bool reuseEligible,
  }) async {
    if (reuseEligible &&
        _connectPhase.offerSessionForReuse(
          connectionString: connectionString,
          connectionId: activeStream.connectionId,
        )) {
      return;
    }
    await _cancelCoordinator.disconnectActiveStream(activeStream);
  }
}
