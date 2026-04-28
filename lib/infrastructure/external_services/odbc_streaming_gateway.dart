import 'dart:async';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart' as app_log;
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
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
class OdbcStreamingGateway implements IStreamingDatabaseGateway {
  OdbcStreamingGateway(
    this._service,
    this._settings, {
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    MetricsCollector? metricsCollector,
  }) : _directConnectionLimiter =
           directConnectionLimiter ??
           DirectOdbcConnectionLimiter(
             maxConcurrent: _settings.poolSize,
             acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
             metricsCollector: metricsCollector,
           ),
       _metrics = metricsCollector;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector? _metrics;
  final Map<String, _ActiveStreamingConnection> _activeStreams = <String, _ActiveStreamingConnection>{};
  bool _initialized = false;
  static const Duration _cancelDisconnectTimeout = Duration(seconds: 8);
  final OdbcAdaptiveBufferCache _adaptiveBufferCache = OdbcAdaptiveBufferCache();

  @override
  bool get hasActiveStream => _activeStreams.isNotEmpty;

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

  Future<Result<void>> _ensureInitialized() async {
    if (_initialized) {
      return const Success(unit);
    }

    final initResult = await _service.initialize();
    return initResult.fold(
      (_) {
        _initialized = true;
        return const Success(unit);
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'initialize_streaming_odbc',
          context: {
            'reason': 'odbc_initialization_failed',
            'user_message': 'Não foi possível inicializar o ambiente ODBC para streaming.',
          },
        ),
      ),
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

    // Conectar com opções otimizadas para streaming
    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: query,
    );
    final leaseResult = await _directConnectionLimiter.acquire(
      operation: 'streaming_query',
    );
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    final connResult = await _service.connect(
      connectionString,
      options: _buildStreamingConnectionOptions(
        chunkSizeBytes,
        hintedBufferBytes: hintedBufferBytes,
        queryTimeout: queryTimeout,
      ),
    );

    return connResult.fold(
      (connection) async {
        final streamExecutionId = executionId ?? connection.id;
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
                      'reason': 'backpressure_overflow',
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
                      'reason': 'socket_disconnect',
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
                await _emitQueryResultRows(queryResult, fetchSize, onChunk);
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
                  _buildStreamingConnectionOptions(
                    chunkSizeBytes,
                    hintedBufferBytes: hintedBufferBytes,
                    queryTimeout: queryTimeout,
                  ).maxResultBufferBytes ??
                  (OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(
                        _settings,
                      ) *
                      1024 *
                      1024),
              errorMessage: e.toString(),
            );
          }
          final context = <String, dynamic>{
            'connectionId': connection.id,
            'executionId': streamExecutionId,
          };
          if (activeStream.cancelReason == StreamingCancelReason.backpressureOverflow) {
            context['rpc_error_code'] = RpcErrorCode.resultTooLarge;
            context['reason'] = 'backpressure_overflow';
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
          _activeStreams.remove(streamExecutionId);
        }
      },
      (error) {
        directLease.release();
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'connect_streaming',
          ),
        );
      },
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
    stream.lease.release();
    try {
      final result = await _service.disconnect(stream.connectionId).timeout(_cancelDisconnectTimeout);
      return result.fold(
        (_) => const Success(unit),
        (error) {
          _metrics?.recordStreamCancelDisconnectFailure();
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'cancel_streaming_disconnect',
              context: {
                'reason': 'stream_cancel_disconnect_failed',
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
            'reason': 'stream_cancel_disconnect_timeout',
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
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk,
  ) async {
    final safeFetchSize = fetchSize > 0 ? fetchSize : 1000;
    var chunk = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final mappedRow = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        mappedRow[result.columns[i]] = row[i];
      }
      chunk.add(mappedRow);
      if (chunk.length >= safeFetchSize) {
        await onChunk(chunk);
        chunk = <Map<String, dynamic>>[];
      }
    }

    if (chunk.isNotEmpty) {
      await onChunk(chunk);
    }
  }
}
