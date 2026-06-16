import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart' as app_log;
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

/// Connect-phase helpers for ODBC streaming: lease acquisition and circuit-breaker connect.
final class OdbcStreamingConnectPhase {
  OdbcStreamingConnectPhase({
    required OdbcService service,
    required ConnectionCircuitBreakerCache circuitBreakers,
    required DirectOdbcConnectionLimiter directConnectionLimiter,
    OdbcStreamingSessionCache? sessionCache,
  }) : _service = service,
       _circuitBreakers = circuitBreakers,
       _directConnectionLimiter = directConnectionLimiter,
       _sessionCache = sessionCache ?? OdbcStreamingSessionCache();

  final OdbcService _service;
  final ConnectionCircuitBreakerCache _circuitBreakers;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final OdbcStreamingSessionCache _sessionCache;

  OdbcStreamingSessionCache get sessionCache => _sessionCache;

  Future<Result<DirectOdbcConnectionLease>> acquireLease({
    required String operation,
  }) {
    return _directConnectionLimiter.acquire(operation: operation);
  }

  Future<Result<Connection>> connectStreaming({
    required String connectionString,
    required ConnectionOptions options,
    required String operation,
  }) async {
    final cachedConnectionId = _sessionCache.tryTake(connectionString);
    if (cachedConnectionId != null) {
      return Success(
        Connection(
          id: cachedConnectionId,
          connectionString: connectionString,
          createdAt: DateTime.now(),
          isActive: true,
        ),
      );
    }

    return connectWithCircuitBreaker(
      connectionString: connectionString,
      options: options,
      operation: operation,
    );
  }

  bool offerSessionForReuse({
    required String connectionString,
    required String connectionId,
  }) {
    return _sessionCache.offer(
      connectionString: connectionString,
      connectionId: connectionId,
    );
  }

  Future<Result<Connection>> connectWithCircuitBreaker({
    required String connectionString,
    required ConnectionOptions options,
    required String operation,
  }) {
    final circuitBreaker = _circuitBreakers.getOrCreate(connectionString);
    return circuitBreaker.execute<Connection>(
      connectionString,
      () async {
        final raw = await _service.connect(connectionString, options: options);
        if (raw.isSuccess()) {
          return Success(raw.getOrThrow());
        }
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            raw.exceptionOrNull()!,
            operation: operation,
          ),
        );
      },
    );
  }

  domain.Failure duplicateExecutionIdFailure({
    required String executionId,
    required String operation,
    bool logWarning = false,
  }) {
    if (logWarning) {
      app_log.AppLogger.warning(
        'executeQueryStream: duplicate executionId rejected ($executionId)',
      );
    }
    return OdbcFailureMapper.mapStreamingError(
      StateError('stream_duplicate_execution_id'),
      operation: operation,
      context: {
        'executionId': executionId,
        'reason': OdbcContextConstants.streamDuplicateExecutionIdReason,
        'user_message':
            'Já existe uma consulta de streaming em andamento com este identificador. '
            'Aguarde a finalização ou use um identificador diferente.',
      },
    );
  }
}
