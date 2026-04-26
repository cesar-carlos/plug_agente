import 'package:plug_agente/domain/protocol/rpc_error_user_message_localizer.dart';

/// JSON-RPC 2.0 Error Codes.
///
/// Defines standard and application-specific error codes for the protocol.
abstract class RpcErrorCode {
  // ============================================================================
  // JSON-RPC 2.0 Standard Errors (-32768 to -32000 reserved)
  // ============================================================================

  /// Invalid JSON received by server.
  static const int parseError = -32700;

  /// JSON is not a valid Request object.
  static const int invalidRequest = -32600;

  /// Method does not exist or is not available.
  static const int methodNotFound = -32601;

  /// Invalid method parameters.
  static const int invalidParams = -32602;

  /// Internal JSON-RPC error.
  static const int internalError = -32603;

  // ============================================================================
  // Transport/Connection Errors (-32099 to -32000)
  // ============================================================================

  /// Authentication failed or invalid token.
  static const int authenticationFailed = -32001;

  /// Not authorized to perform operation.
  static const int unauthorized = -32002;

  /// Server or network timeout.
  static const int timeout = -32008;

  /// Invalid payload format or encoding.
  static const int invalidPayload = -32009;

  /// Failed to decompress or decode payload.
  static const int decodingFailed = -32010;

  /// Compression failed.
  static const int compressionFailed = -32011;

  /// Network connection error.
  static const int networkError = -32012;

  /// Event-level rate limit exceeded.
  static const int rateLimited = -32013;

  /// Duplicate request detected within replay window.
  static const int replayDetected = -32014;

  // ============================================================================
  // SQL Domain Errors (-32199 to -32100)
  // ============================================================================

  /// SQL validation failed (syntax, injection check, etc).
  static const int sqlValidationFailed = -32101;

  /// SQL execution failed.
  static const int sqlExecutionFailed = -32102;

  /// Database transaction failed.
  static const int transactionFailed = -32103;

  /// Connection pool exhausted.
  static const int connectionPoolExhausted = -32104;

  /// Result set too large.
  static const int resultTooLarge = -32105;

  /// Database connection failed.
  static const int databaseConnectionFailed = -32106;

  /// Query timeout.
  static const int queryTimeout = -32107;

  /// Invalid database configuration.
  static const int invalidDatabaseConfig = -32108;

  /// Execution not found for cancel operation.
  static const int executionNotFound = -32109;

  /// Query execution was cancelled.
  static const int executionCancelled = -32110;

  // ============================================================================
  // Error data catalog helpers
  // ============================================================================

  static const String categoryValidation = 'validation';
  static const String categoryAuth = 'auth';
  static const String categoryNetwork = 'network';
  static const String categoryTransport = 'transport';
  static const String categorySql = 'sql';
  static const String categoryDatabase = 'database';
  static const String categoryInternal = 'internal';

  /// Use in [buildErrorData] `reason` when [-32001] is due to bad HMAC/signature.
  static const String reasonInvalidSignature = 'invalid_signature';

  // ============================================================================
  // Helper methods
  // ============================================================================

  /// Returns a human-readable message for the error code.
  static String getMessage(int code) {
    return switch (code) {
      parseError => 'Parse error',
      invalidRequest => 'Invalid Request',
      methodNotFound => 'Method not found',
      invalidParams => 'Invalid params',
      internalError => 'Internal error',
      authenticationFailed => 'Authentication failed',
      unauthorized => 'Not authorized',
      timeout => 'Timeout',
      invalidPayload => 'Invalid payload',
      decodingFailed => 'Decoding failed',
      compressionFailed => 'Compression failed',
      networkError => 'Network error',
      rateLimited => 'Rate limit exceeded',
      replayDetected => 'Replay detected',
      sqlValidationFailed => 'SQL validation failed',
      sqlExecutionFailed => 'SQL execution failed',
      transactionFailed => 'Transaction failed',
      connectionPoolExhausted => 'Connection pool exhausted',
      resultTooLarge => 'Result too large',
      databaseConnectionFailed => 'Database connection failed',
      queryTimeout => 'Query timeout',
      invalidDatabaseConfig => 'Invalid database configuration',
      executionNotFound => 'Execution not found',
      executionCancelled => 'Execution cancelled',
      _ => 'Server error',
    };
  }

  /// Returns whether the error is transient (retryable).
  static bool isTransient(int code) {
    return switch (code) {
      timeout ||
      networkError ||
      rateLimited ||
      connectionPoolExhausted ||
      queryTimeout ||
      databaseConnectionFailed => true,
      _ => false,
    };
  }

  /// Returns whether the error is recoverable (client can fix it).
  static bool isRecoverable(int code) {
    return switch (code) {
      invalidRequest ||
      methodNotFound ||
      invalidParams ||
      authenticationFailed ||
      unauthorized ||
      rateLimited ||
      replayDetected ||
      invalidPayload ||
      sqlValidationFailed ||
      invalidDatabaseConfig => true,
      _ => false,
    };
  }

  /// Returns the HTTP-style status code for semantic mapping.
  static int getStatus(int code) {
    return switch (code) {
      parseError || invalidRequest || invalidParams || invalidPayload => 400,
      authenticationFailed => 401,
      unauthorized => 403,
      methodNotFound => 404,
      sqlValidationFailed => 422,
      timeout || queryTimeout => 408,
      rateLimited => 429,
      replayDetected => 409,
      internalError ||
      sqlExecutionFailed ||
      transactionFailed ||
      compressionFailed ||
      decodingFailed ||
      connectionPoolExhausted ||
      resultTooLarge ||
      networkError ||
      databaseConnectionFailed ||
      executionNotFound ||
      executionCancelled => 500,
      _ => 500,
    };
  }

  /// Returns an error category for [`code`].
  static String getCategory(int code) {
    return switch (code) {
      parseError || invalidRequest || methodNotFound || invalidParams => categoryValidation,
      authenticationFailed || unauthorized => categoryAuth,
      timeout || networkError => categoryNetwork,
      invalidPayload || decodingFailed || compressionFailed || rateLimited || replayDetected => categoryTransport,
      sqlValidationFailed || sqlExecutionFailed || transactionFailed || resultTooLarge || queryTimeout => categorySql,
      connectionPoolExhausted ||
      databaseConnectionFailed ||
      invalidDatabaseConfig ||
      executionNotFound ||
      executionCancelled => categoryDatabase,
      // Explicit arm for internalError so the catch-all `_` is reserved for
      // codes that genuinely have no mapping yet (forward-compat).
      internalError => categoryInternal,
      _ => categoryInternal,
    };
  }

  /// Returns a stable automation-oriented reason for [`code`].
  static String getReason(int code) {
    return switch (code) {
      parseError => 'json_parse_error',
      invalidRequest => 'invalid_request',
      methodNotFound => 'method_not_found',
      invalidParams => 'invalid_params',
      internalError => 'internal_error',
      authenticationFailed => 'authentication_failed',
      unauthorized => 'unauthorized',
      timeout => 'timeout',
      invalidPayload => 'invalid_payload',
      decodingFailed => 'decoding_failed',
      compressionFailed => 'compression_failed',
      networkError => 'network_error',
      rateLimited => 'rate_limited',
      replayDetected => 'replay_detected',
      sqlValidationFailed => 'sql_validation_failed',
      sqlExecutionFailed => 'sql_execution_failed',
      transactionFailed => 'transaction_failed',
      connectionPoolExhausted => 'connection_pool_exhausted',
      resultTooLarge => 'result_too_large',
      databaseConnectionFailed => 'database_connection_failed',
      queryTimeout => 'query_timeout',
      invalidDatabaseConfig => 'invalid_database_config',
      executionNotFound => 'execution_not_found',
      executionCancelled => 'execution_cancelled',
      _ => 'internal_error',
    };
  }

  /// Pluggable localizer slot. Presentation layer may install an
  /// AppLocalizations-backed implementation at boot time. Defaults to PT-BR.
  static RpcErrorUserMessageLocalizer userMessageLocalizer = const DefaultPtRpcErrorUserMessageLocalizer();

  /// Returns a user-facing localized message for [`code`]. Routes through
  /// [userMessageLocalizer] so callers can swap the locale globally.
  static String getUserMessage(int code) {
    final l = userMessageLocalizer;
    return switch (code) {
      parseError || invalidRequest || invalidParams => l.invalidRequest(),
      methodNotFound => l.methodNotFound(),
      authenticationFailed => l.authenticationFailed(),
      unauthorized => l.unauthorized(),
      timeout || queryTimeout => l.timeout(),
      invalidPayload || decodingFailed || compressionFailed => l.invalidPayload(),
      networkError => l.networkError(),
      rateLimited => l.rateLimited(),
      replayDetected => l.replayDetected(),
      sqlValidationFailed => l.sqlValidationFailed(),
      sqlExecutionFailed || transactionFailed => l.sqlExecutionFailed(),
      connectionPoolExhausted => l.connectionPoolExhausted(),
      resultTooLarge => l.resultTooLarge(),
      databaseConnectionFailed => l.databaseConnectionFailed(),
      invalidDatabaseConfig => l.invalidDatabaseConfig(),
      executionNotFound => l.executionNotFound(),
      executionCancelled => l.executionCancelled(),
      _ => l.internalError(),
    };
  }

  /// Creates a deterministic-ish correlation identifier.
  static String createCorrelationId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'corr-$now';
  }

  /// Builds standardized error data payload.
  ///
  /// `subreason` is preserved separately from the canonical `reason`. Use it to
  /// communicate a more specific cause without overriding the wire-stable
  /// `reason` field that automation pipelines key on. Example: `code` is
  /// [resultTooLarge] (canonical reason `result_too_large`) but the underlying
  /// trigger was `backpressure_overflow` — pass that as `subreason`.
  ///
  /// Note: keys present in [extra] are merged last and DO override anything
  /// computed above them. Avoid putting `reason` in `extra`; prefer `subreason`.
  static Map<String, dynamic> buildErrorData({
    required int code,
    required String technicalMessage,
    String? correlationId,
    DateTime? timestamp,
    bool? retryable,
    String? category,
    String? reason,
    String? subreason,
    String? userMessage,
    Map<String, dynamic> extra = const {},
  }) {
    final resolvedCorrelationId = correlationId ?? createCorrelationId();
    final resolvedTimestamp = (timestamp ?? DateTime.now()).toUtc();
    final resolvedCategory = category ?? getCategory(code);
    final resolvedReason = reason ?? getReason(code);
    final resolvedRetryable = retryable ?? isTransient(code);
    final resolvedUserMessage = userMessage ?? getUserMessage(code);

    return <String, dynamic>{
      'reason': resolvedReason,
      // ignore: use_null_aware_elements - older Dart compatibility
      if (subreason != null) 'subreason': subreason,
      'category': resolvedCategory,
      'retryable': resolvedRetryable,
      'user_message': resolvedUserMessage,
      'technical_message': technicalMessage,
      'correlation_id': resolvedCorrelationId,
      'timestamp': resolvedTimestamp.toIso8601String(),
      ...extra,
    };
  }
}
