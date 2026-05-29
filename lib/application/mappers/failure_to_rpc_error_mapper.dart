import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_error_data_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/core/utils/odbc_message_sanitizer.dart';
import 'package:plug_agente/core/utils/sensitive_map_redactor.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
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
  /// Failure-context key holding the verbatim ODBC driver message. Kept local
  /// for diagnostics; never forwarded across the RPC boundary.
  static const String _odbcMessageContextKey = 'odbc_message';

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

    if (failure is ActionValidationFailure) {
      if (failure.code == AgentActionFailureCode.featureDisabled) {
        return RpcErrorCode.agentActionsTemporarilyUnavailable;
      }
      return RpcErrorCode.invalidParams;
    }
    if (failure is ActionAuthorizationFailure) {
      if (failure.code == AgentActionFailureCode.subsystemStarting ||
          failure.code == AgentActionFailureCode.subsystemDraining ||
          failure.code == AgentActionFailureCode.subsystemDegraded ||
          failure.code == AgentActionFailureCode.maintenanceMode ||
          failure.code == AgentActionFailureCode.elevatedDisabled ||
          failure.code == AgentActionFailureCode.elevatedNotConfigured ||
          failure.code == AgentActionFailureCode.elevatedRunnerDegraded) {
        return RpcErrorCode.agentActionsTemporarilyUnavailable;
      }
      return RpcErrorCode.unauthorized;
    }
    if (failure is ActionNotFoundFailure) {
      return RpcErrorCode.executionNotFound;
    }
    if (failure is ActionQueueFailure) {
      if (failure.code == AgentActionFailureCode.queueFull) {
        return RpcErrorCode.rateLimited;
      }
      if (failure.code == AgentActionFailureCode.queueTimeout) {
        return RpcErrorCode.timeout;
      }
      if (failure.code == AgentActionFailureCode.queueConcurrencyRejected ||
          failure.code == AgentActionFailureCode.queueIgnored) {
        return RpcErrorCode.invalidParams;
      }
      return RpcErrorCode.internalError;
    }
    if (failure is ActionTimeoutFailure) {
      return RpcErrorCode.timeout;
    }
    if (failure is ActionRuntimeFailure) {
      if (failure.code == AgentActionFailureCode.alreadyFinished ||
          failure.code == AgentActionFailureCode.cancelNotRunning ||
          failure.code == AgentActionFailureCode.pathSnapshotMismatch ||
          failure.code == AgentActionFailureCode.preflightRequiredForActive ||
          failure.code == AgentActionFailureCode.preflightExpiredForActive ||
          // secretUnavailable can surface as either ActionValidationFailure (gate)
          // or ActionRuntimeFailure (resolution at execution time). Both deserve
          // invalidParams so the Hub sees a stable contract error, not a 500.
          failure.code == AgentActionFailureCode.secretUnavailable) {
        return RpcErrorCode.invalidParams;
      }
      if (failure.code == AgentActionFailureCode.executionCancelled ||
          failure.code == AgentActionFailureCode.executionKilled) {
        return RpcErrorCode.executionCancelled;
      }
      if (failure.code == AgentActionFailureCode.elevatedSubmitFailed ||
          failure.code == AgentActionFailureCode.elevatedRequestProtectionFailed) {
        return RpcErrorCode.agentActionsTemporarilyUnavailable;
      }
      return RpcErrorCode.internalError;
    }

    if (failure is ValidationFailure) {
      if (failure.context['operation'] == 'sql_validation') {
        return RpcErrorCode.sqlValidationFailed;
      }
      return RpcErrorCode.invalidParams;
    }

    if (failure is QueryExecutionFailure) {
      if (_isPermissionDeniedFailure(failure.context)) {
        return RpcErrorCode.unauthorized;
      }
      if (failure.context['reason'] == OdbcContextConstants.transactionFailedReason ||
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
      // NotFoundFailure represents a missing **resource** (HTTP 404, missing
      // config row, etc.) — NOT a missing JSON-RPC method. JSON-RPC reserves
      // -32601 strictly for "method does not exist". Map resource-not-found to
      // internalError with a structured `reason: RpcErrorDataConstants.resourceNotFoundReason` so
      // automation does not confuse it with a typo in `request.method`.
      return RpcErrorCode.internalError;
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
    // The verbatim ODBC driver message (server/database/user identifiers) is
    // kept on the local Failure for in-app diagnostics, but must not be
    // forwarded across the RPC boundary to the hub.
    contextForExtra.remove(_odbcMessageContextKey);
    final clientDetail = OdbcMessageSanitizer.sanitize(failure.message);
    final rawContextReason = contextForExtra.remove('reason');
    final domainReason = _stringifyOptionalReason(rawContextReason);
    final timeoutReason = _getTimeoutReasonOverride(
      failure,
      code,
      useTimeoutByStage,
    );
    final customReason = _getCustomReasonOverride(failure, code);
    final resolvedReason = timeoutReason ?? customReason ?? RpcErrorCode.getReason(code);
    final subreasonForPayload = _subreasonIfDistinct(domainReason, resolvedReason);
    final odbcReasonForPayload = _odbcReasonIfDistinct(domainReason, resolvedReason);
    final extra = <String, dynamic>{
      'type': _getTypeUri(failure, code),
      'title': RpcErrorCode.getMessage(code),
      'status': RpcErrorCode.getStatus(code),
      'detail': clientDetail,
      ...(instance != null ? {'instance': instance} : {}),
      'recoverable': RpcErrorCode.isRecoverable(code),
      'failure_code': failure.code,
      ...contextForExtra,
      if (subreasonForPayload case final String r) 'subreason': r,
      if (odbcReasonForPayload case final String r) 'odbc_reason': r,
      'reason': resolvedReason,
    };

    return RpcErrorCode.buildErrorData(
      code: code,
      technicalMessage: clientDetail,
      correlationId: correlationId,
      timestamp: failure.timestamp,
      retryable: RpcErrorCode.isTransient(code),
      category: _categoryForFailure(failure),
      extra: extra,
    );
  }

  /// Agent-action failures share `category: action` in MVP 3; numeric codes stay
  /// on transport/auth/validation until the reserved -322xx band is allocated.
  static String? _categoryForFailure(Failure failure) {
    return switch (failure) {
      ActionValidationFailure() ||
      ActionAuthorizationFailure() ||
      ActionNotFoundFailure() ||
      ActionQueueFailure() ||
      ActionTimeoutFailure() ||
      ActionRuntimeFailure() => RpcErrorCode.categoryAction,
      _ => null,
    };
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
    if (_isQueueOrBackpressureReason(odbcReason)) {
      return null;
    }
    return odbcReason == resolvedReason ? null : odbcReason;
  }

  static String? _subreasonIfDistinct(String? domainReason, String resolvedReason) {
    if (domainReason == null || !_isQueueOrBackpressureReason(domainReason)) {
      return null;
    }
    return domainReason == resolvedReason ? null : domainReason;
  }

  static bool _isQueueOrBackpressureReason(String reason) {
    return switch (reason) {
      SqlPipelineContextConstants.sqlQueueFullReason ||
      SqlPipelineContextConstants.queueWaitTimeoutReason ||
      SqlPipelineContextConstants.queueDisposedReason ||
      RpcStreamingConstants.backpressureOverflowReason => true,
      _ => false,
    };
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

  /// Per-failure-type reason overrides that win over the canonical reason
  /// derived from the RPC code. Use this for cases where the same RPC code
  /// (e.g. `internalError`) needs different `reason` strings depending on the
  /// originating failure type so automation pipelines can distinguish them.
  static String? _getCustomReasonOverride(Failure failure, int code) {
    if (failure is ConfigurationFailure && code == RpcErrorCode.authenticationFailed) {
      final reason = failure.context['reason']?.toString();
      if (reason == RpcClientTokenConstants.missingClientTokenReason) {
        return reason;
      }
    }
    if (failure is NotFoundFailure && code == RpcErrorCode.internalError) {
      return RpcErrorDataConstants.resourceNotFoundReason;
    }
    if (failure is ActionValidationFailure &&
        code == RpcErrorCode.agentActionsTemporarilyUnavailable &&
        failure.code == AgentActionFailureCode.featureDisabled) {
      return AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason;
    }
    if (failure is ActionValidationFailure && code == RpcErrorCode.invalidParams) {
      if (failure.code == AgentActionFailureCode.remoteContextNotSupported) {
        return AgentActionRpcConstants.remoteContextNotSupportedRpcReason;
      }
      if (failure.code == AgentActionFailureCode.remoteIdempotencyRequired) {
        return AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason;
      }
      final reason = failure.context['reason']?.toString();
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    if (failure is ActionAuthorizationFailure) {
      if (code == RpcErrorCode.unauthorized) {
        if (failure.code == AgentActionFailureCode.remoteFeatureDisabled) {
          return AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason;
        }
        if (failure.code == AgentActionFailureCode.remoteAdHocDisabled) {
          return AgentActionRpcConstants.agentActionsRemoteAdHocDisabledErrorReason;
        }
        if (failure.code == AgentActionFailureCode.featureDisabled) {
          return AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason;
        }
        final reason = failure.context['reason']?.toString();
        if (reason == AgentActionRpcConstants.agentActionPermissionDeniedErrorReason) {
          return AgentActionRpcConstants.agentActionPermissionDeniedErrorReason;
        }
        if (reason != null && reason.isNotEmpty) {
          return reason;
        }
      }
      if (code == RpcErrorCode.agentActionsTemporarilyUnavailable) {
        // Always use the canonical RPC reason for maintenance, regardless of
        // which internal constant the guard stored in context['reason'].
        if (failure.code == AgentActionFailureCode.maintenanceMode) {
          return AgentActionRpcConstants.agentActionsMaintenanceModeErrorReason;
        }
        final reason = failure.context['reason']?.toString();
        if (reason != null && reason.isNotEmpty) {
          return reason;
        }
      }
    }
    if (failure is ActionRuntimeFailure && code == RpcErrorCode.agentActionsTemporarilyUnavailable) {
      final reason = failure.context['reason']?.toString();
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    // Action runtime failures that map to invalidParams (secret unavailable,
    // path snapshot mismatch, preflight expired/required) should preserve the
    // domain `reason` so automation gets the actionable cause, not the generic
    // canonical `invalid_params`.
    if (failure is ActionRuntimeFailure && code == RpcErrorCode.invalidParams) {
      final reason = failure.context['reason']?.toString();
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    return null;
  }

  static bool _isSensitiveKey(String key) => SensitiveMapRedactor.isSensitiveKey(key);

  static bool _isPermissionDeniedFailure(Map<String, dynamic> context) {
    final reason = context['reason']?.toString();
    if (reason == 'sql_permission_denied' || reason == 'missing_permission') {
      return true;
    }
    final sqlState = context['odbc_sql_state']?.toString().toUpperCase();
    return sqlState == '42501';
  }

  static Map<String, dynamic> _sanitizeContext(Map<String, dynamic> context) {
    return Map.fromEntries(
      context.entries.where((e) => !_isSensitiveKey(e.key)),
    );
  }
}
