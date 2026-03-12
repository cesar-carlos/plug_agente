import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

/// Maps domain Failures to RPC errors.
class FailureToRpcErrorMapper {
  /// Converts a Failure to an RpcError with Problem Details data.
  ///
  /// When [useTimeoutByStage] is true, uses `timeout_stage` from failure
  /// context to classify timeouts (sql, transport, ack) for finer error codes.
  static RpcError map(
    Failure failure, {
    String? instance,
    bool useTimeoutByStage = false,
  }) {
    final code = _getErrorCode(failure, useTimeoutByStage);
    final message = RpcErrorCode.getMessage(code);
    final data = _buildErrorData(failure, code, instance, useTimeoutByStage);

    return RpcError(
      code: code,
      message: message,
      data: data,
    );
  }

  /// Determines the RPC error code based on failure type.
  static int _getErrorCode(Failure failure, bool useTimeoutByStage) {
    if (failure is ValidationFailure) {
      // Check context for SQL-specific validation
      if (failure.context['operation'] == 'sql_validation') {
        return RpcErrorCode.sqlValidationFailed;
      }
      return RpcErrorCode.invalidParams;
    }

    if (failure is QueryExecutionFailure) {
      if (failure.context['timeout'] == true) {
        return RpcErrorCode.queryTimeout;
      }
      if (useTimeoutByStage && failure.context['timeout_stage'] == 'sql') {
        return RpcErrorCode.queryTimeout;
      }
      return RpcErrorCode.sqlExecutionFailed;
    }

    if (failure is DatabaseFailure) {
      if (failure.context['poolExhausted'] == true) {
        return RpcErrorCode.connectionPoolExhausted;
      }
      if (failure.context['connectionFailed'] == true) {
        return RpcErrorCode.databaseConnectionFailed;
      }
      return RpcErrorCode.sqlExecutionFailed;
    }

    if (failure is NetworkFailure) {
      if (failure.context['timeout'] == true) {
        return RpcErrorCode.timeout;
      }
      if (useTimeoutByStage) {
        final stage = failure.context['timeout_stage'] as String?;
        if (stage == 'transport' || stage == 'ack') {
          return RpcErrorCode.timeout;
        }
      }
      return RpcErrorCode.networkError;
    }

    if (failure is ConfigurationFailure) {
      if (failure.context['authentication'] == true) {
        return RpcErrorCode.authenticationFailed;
      }
      if (failure.context['authorization'] == true) {
        return RpcErrorCode.unauthorized;
      }
      if (failure.context['database'] == true) {
        return RpcErrorCode.invalidDatabaseConfig;
      }
      return RpcErrorCode.invalidRequest;
    }

    if (failure is ConnectionFailure) {
      return RpcErrorCode.networkError;
    }

    if (failure is CompressionFailure) {
      if (failure.context['operation'] == 'decompress') {
        return RpcErrorCode.decodingFailed;
      }
      return RpcErrorCode.compressionFailed;
    }

    if (failure is ServerFailure) {
      return RpcErrorCode.internalError;
    }

    if (failure is NotFoundFailure) {
      return RpcErrorCode.methodNotFound;
    }

    // Default to internal error
    return RpcErrorCode.internalError;
  }

  /// Builds standardized error data from failure.
  static Map<String, dynamic> _buildErrorData(
    Failure failure,
    int code,
    String? instance,
    bool useTimeoutByStage,
  ) {
    final correlationId = instance ?? RpcErrorCode.createCorrelationId();
    final safeContext = _sanitizeContext(failure.context);
    final timeoutReason = _getTimeoutReasonOverride(
      failure,
      code,
      useTimeoutByStage,
    );
    final extra = <String, dynamic>{
      // Legacy/problem-details-compatible fields for transition.
      'type': _getTypeUri(failure),
      'title': RpcErrorCode.getMessage(code),
      'status': RpcErrorCode.getStatus(code),
      'detail': failure.message,
      ...(instance != null ? {'instance': instance} : {}),
      // Additional diagnostics.
      'recoverable': failure.isRecoverable,
      'failure_code': failure.code,
      ...safeContext,
      ...?(timeoutReason != null ? {'reason': timeoutReason} : null),
    };

    return RpcErrorCode.buildErrorData(
      code: code,
      technicalMessage: failure.message,
      correlationId: correlationId,
      timestamp: failure.timestamp,
      retryable: failure.isTransient,
      extra: extra,
    );
  }

  /// Generates a type URI for the failure.
  static String _getTypeUri(Failure failure) {
    const baseUri = 'https://plugdb.dev/problems';

    if (failure is ValidationFailure) return '$baseUri/validation-error';
    if (failure is QueryExecutionFailure) {
      return '$baseUri/query-execution-error';
    }
    if (failure is DatabaseFailure) return '$baseUri/database-error';
    if (failure is NetworkFailure) return '$baseUri/network-error';
    if (failure is ConfigurationFailure) return '$baseUri/configuration-error';
    if (failure is ConnectionFailure) return '$baseUri/connection-error';
    if (failure is CompressionFailure) return '$baseUri/compression-error';
    if (failure is ServerFailure) return '$baseUri/server-error';
    if (failure is NotFoundFailure) return '$baseUri/not-found';

    return '$baseUri/internal-error';
  }

  /// Returns reason override for timeout-by-stage classification.
  static String? _getTimeoutReasonOverride(
    Failure failure,
    int code,
    bool useTimeoutByStage,
  ) {
    if (!useTimeoutByStage || code != RpcErrorCode.timeout) {
      return null;
    }
    final stage = failure.context['timeout_stage'] as String?;
    return switch (stage) {
      'transport' => 'transport_timeout',
      'ack' => 'ack_timeout',
      _ => null,
    };
  }

  /// Removes sensitive information from context.
  static Map<String, dynamic> _sanitizeContext(Map<String, dynamic> context) {
    const sensitiveKeys = {
      'password',
      'token',
      'secret',
      'apiKey',
      'connectionString',
    };

    return Map.fromEntries(
      context.entries.where((e) => !sensitiveKeys.contains(e.key)),
    );
  }
}
