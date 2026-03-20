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
import 'package:result_dart/result_dart.dart';

/// Gateway com suporte a streaming real para grandes datasets.
///
/// Implementa streaming incremental usando streamQuery da odbc_fast,
/// processando resultados em chunks sem carregar tudo em memória.
class OdbcStreamingGateway implements IStreamingDatabaseGateway {
  OdbcStreamingGateway(this._service, this._settings);
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  String? _activeConnectionId;
  bool _isCancelRequested = false;
  StreamingCancelReason _cancelReason = StreamingCancelReason.user;
  bool _initialized = false;
  static const Duration _cancelDisconnectTimeout = Duration(seconds: 3);

  @override
  bool get hasActiveStream => _activeConnectionId != null;

  ConnectionOptions _buildStreamingConnectionOptions(int chunkSizeBytes) {
    final normalizedChunkSize = max(chunkSizeBytes, 64 * 1024);
    final maxResultBufferBytes = max(
      normalizedChunkSize,
      _settings.maxResultBufferMb * 1024 * 1024,
    );
    final initialResultBufferBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      maxResultBufferBytes,
    );

    return ConnectionOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: const Duration(minutes: 5),
      maxResultBufferBytes: maxResultBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }

  /// Helper para converter erros ODBC em String.
  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
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
    void Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
  }) async {
    _isCancelRequested = false;
    _cancelReason = StreamingCancelReason.user;

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
    final connResult = await _service.connect(
      connectionString,
      options: _buildStreamingConnectionOptions(chunkSizeBytes),
    );

    return connResult.fold(
      (connection) async {
        _activeConnectionId = connection.id;
        try {
          // Usar streaming real para processar chunks incrementalmente
          await for (final chunkResult in _service.streamQuery(
            connection.id,
            query,
          )) {
            if (_isCancelRequested) {
              if (_cancelReason == StreamingCancelReason.playgroundRowCap) {
                return const Success(unit);
              }
              if (_cancelReason == StreamingCancelReason.backpressureOverflow) {
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
              if (_cancelReason == StreamingCancelReason.socketDisconnect) {
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
                // Converter chunk e notificar callback
                final rows = _convertQueryResultToMaps(queryResult);
                if (rows.isNotEmpty) {
                  _chunkRows(rows, fetchSize).forEach(onChunk);
                }
              },
              (error) {
                throw Exception(_odbcErrorMessage(error));
              },
            );
          }

          return const Success(unit);
        } on Exception catch (e) {
          final context = <String, dynamic>{
            'connectionId': connection.id,
          };
          if (_cancelReason == StreamingCancelReason.backpressureOverflow) {
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
          await _service.disconnect(connection.id);
          if (_activeConnectionId == connection.id) {
            _activeConnectionId = null;
          }
        }
      },
      (error) {
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
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    final activeConnectionId = _activeConnectionId;
    if (activeConnectionId == null) {
      return const Success(unit);
    }

    _cancelReason = reason;
    _isCancelRequested = true;
    try {
      final result = await _service.disconnect(activeConnectionId).timeout(_cancelDisconnectTimeout);
      return result.fold(
        (_) => const Success(unit),
        (error) => Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'cancel_streaming_disconnect',
            context: {
              'reason': 'stream_cancel_disconnect_failed',
              'user_message':
                  'A consulta foi marcada para cancelamento, mas a desconexão '
                  'do streaming não foi confirmada imediatamente.',
            },
          ),
        ),
      );
    } on TimeoutException {
      return const Success(unit);
    } finally {
      if (_activeConnectionId == activeConnectionId) {
        _activeConnectionId = null;
      }
    }
  }

  Iterable<List<Map<String, dynamic>>> _chunkRows(
    List<Map<String, dynamic>> rows,
    int fetchSize,
  ) sync* {
    final safeFetchSize = fetchSize > 0 ? fetchSize : 1000;
    for (var i = 0; i < rows.length; i += safeFetchSize) {
      final end = min(i + safeFetchSize, rows.length);
      yield rows.sublist(i, end);
    }
  }

  /// Converte QueryResult para lista de maps.
  List<Map<String, dynamic>> _convertQueryResultToMaps(QueryResult result) {
    return result.rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        map[result.columns[i]] = row[i];
      }
      return map;
    }).toList();
  }
}
