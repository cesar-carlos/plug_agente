import 'package:plug_agente/core/utils/sensitive_map_redactor.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

/// Maps domain Failures to RPC errors.
///
/// Connection issues from the database driver typically use [ConnectionFailure]
/// (connect/pool). Session loss during SQL execution may use [QueryExecutionFailure]
/// with `connectionFailed: true`. Prefer [DatabaseFailure] only where repositories
/// already emit that type.
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
    final data = _buildErrorData(
      failure,
      code,
      instance,
      useTimeoutByStage,
    );

    return RpcError(
      code: code,
      message: message,
      data: data,
    );
  }

  /// Determines the RPC error code based on failure type.
  static int _getErrorCode(Failure failure, bool useTimeoutByStage) {
    final override = failure.context['rpc_error_code'];
    if (override is int) {
      return override;
    }

    if (failure is ValidationFailure) {
      if (failure.context['operation'] == 'sql_validation') {
        return RpcErrorCode.sqlValidationFailed;
      }
      return RpcErrorCode.invalidParams;
    }

    if (failure is QueryExecutionFailure) {
      if (failure.context['reason'] == 'transaction_failed' ||
          failure.context['operation'] == 'transaction' ||
          ((failure.context['operation'] as String?)?.startsWith(
                'transaction_',
              ) ??
              false)) {
        return RpcErrorCode.transactionFailed;
      }
      if (failure.context['connectionFailed'] == true) {
        return RpcErrorCode.databaseConnectionFailed;
      }
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
      if (failure.context['poolExhausted'] == true) {
        return RpcErrorCode.connectionPoolExhausted;
      }
      return RpcErrorCode.databaseConnectionFailed;
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
    final contextForExtra = Map<String, dynamic>.from(safeContext);
    final rawContextReason = contextForExtra.remove('reason');
    final odbcReason = _stringifyOptionalReason(rawContextReason);
    final timeoutReason = _getTimeoutReasonOverride(
      failure,
      code,
      useTimeoutByStage,
    );
    final resolvedReason = timeoutReason ?? RpcErrorCode.getReason(code);
    final odbcReasonForPayload = _odbcReasonIfDistinct(odbcReason, resolvedReason);
    final extra = <String, dynamic>{
      'type': _getTypeUri(failure, code),
      'title': RpcErrorCode.getMessage(code),
      'status': RpcErrorCode.getStatus(code),
      'detail': failure.message,
      ...(instance != null ? {'instance': instance} : {}),
      'recoverable': RpcErrorCode.isRecoverable(code),
      'failure_code': failure.code,
      ...contextForExtra,
      if (odbcReasonForPayload case final String r) 'odbc_reason': r,
      'reason': resolvedReason,
    };

    return RpcErrorCode.buildErrorData(
      code: code,
      technicalMessage: failure.message,
      correlationId: correlationId,
      timestamp: failure.timestamp,
      retryable: RpcErrorCode.isTransient(code),
      extra: extra,
    );
  }

  static String? _stringifyOptionalReason(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Omits domain sub-reason when it matches the canonical [resolvedReason].
  static String? _odbcReasonIfDistinct(String? odbcReason, String resolvedReason) {
    if (odbcReason == null) {
      return null;
    }
    return odbcReason == resolvedReason ? null : odbcReason;
  }

  static String _getTypeUri(Failure failure, int code) {
    const baseUri = 'https://plugdb.dev/problems';

    return switch (code) {
      RpcErrorCode.parseError ||
      RpcErrorCode.invalidRequest ||
      RpcErrorCode.invalidParams ||
      RpcErrorCode.sqlValidationFailed => '$baseUri/validation-error',
      RpcErrorCode.methodNotFound => '$baseUri/not-found',
      RpcErrorCode.authenticationFailed || RpcErrorCode.unauthorized => '$baseUri/configuration-error',
      RpcErrorCode.timeout || RpcErrorCode.networkError => '$baseUri/network-error',
      RpcErrorCode.invalidPayload ||
      RpcErrorCode.rateLimited ||
      RpcErrorCode.replayDetected => '$baseUri/internal-error',
      RpcErrorCode.decodingFailed || RpcErrorCode.compressionFailed => '$baseUri/compression-error',
      RpcErrorCode.sqlExecutionFailed ||
      RpcErrorCode.transactionFailed ||
      RpcErrorCode.resultTooLarge ||
      RpcErrorCode.queryTimeout => '$baseUri/query-execution-error',
      RpcErrorCode.connectionPoolExhausted ||
      RpcErrorCode.databaseConnectionFailed ||
      RpcErrorCode.invalidDatabaseConfig ||
      RpcErrorCode.executionNotFound ||
      RpcErrorCode.executionCancelled => '$baseUri/database-error',
      RpcErrorCode.internalError => '$baseUri/server-error',
      _ => _getTypeUriFallback(failure),
    };
  }

  static String _getTypeUriFallback(Failure failure) {
    const baseUri = 'https://plugdb.dev/problems';

    if (failure is ValidationFailure) {
      return '$baseUri/validation-error';
    }
    if (failure is QueryExecutionFailure) {
      return '$baseUri/query-execution-error';
    }
    if (failure is DatabaseFailure) {
      return '$baseUri/database-error';
    }
    if (failure is NetworkFailure) {
      return '$baseUri/network-error';
    }
    if (failure is ConfigurationFailure) {
      return '$baseUri/configuration-error';
    }
    if (failure is ConnectionFailure) {
      return '$baseUri/database-error';
    }
    if (failure is CompressionFailure) {
      return '$baseUri/compression-error';
    }
    if (failure is ServerFailure) {
      return '$baseUri/server-error';
    }
    if (failure is NotFoundFailure) {
      return '$baseUri/not-found';
    }

    return '$baseUri/internal-error';
  }

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

  static bool _isSensitiveKey(String key) => SensitiveMapRedactor.isSensitiveKey(key);

  static Map<String, dynamic> _sanitizeContext(Map<String, dynamic> context) {
    return Map.fromEntries(
      context.entries.where((e) => !_isSensitiveKey(e.key)),
    );
  }
}
