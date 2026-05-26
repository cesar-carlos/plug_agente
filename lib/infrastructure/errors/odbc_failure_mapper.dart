import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

class OdbcFailureMapper {
  OdbcFailureMapper._();

  static const int _kMaxDeniedResourcesInUserMessage = 5;
  static final RegExp _sqlServerPermissionObjectPattern = RegExp(
    r"permission\s+was\s+denied\s+on\s+(?:the\s+)?object\s+'([^']+)'(?:,\s*database\s*'[^']+')?(?:,\s*schema\s*'([^']+)')?",
    caseSensitive: false,
  );
  static final RegExp _postgresPermissionPattern = RegExp(
    r'permission\s+denied\s+for\s+(?:table|relation|view|sequence)\s+"?([a-z0-9_$.]+)"?',
    caseSensitive: false,
  );
  static final RegExp _quotedResourcePattern = RegExp(
    "(?:table|object|relation|view)\\s+['\\\"]([^'\\\"]+)['\\\"]",
    caseSensitive: false,
  );

  static Failure mapConnectionError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final sqlState = _extractSqlState(error);
    final baseContext = _buildBaseContext(error, operation, context);

    if (error is WorkerCrashedError) {
      return ConnectionFailure.withContext(
        message: 'ODBC worker was interrupted',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': true,
          'reason': OdbcContextConstants.odbcWorkerCrashedReason,
          'user_message': 'The ODBC connection was interrupted internally. Try running the operation again.',
        },
      );
    }

    if (_isDriverMissing(sqlState, detail)) {
      return ConfigurationFailure.withContext(
        message: 'ODBC driver not found or not configured',
        cause: error,
        context: {
          ...baseContext,
          'database': true,
          'reason': OdbcContextConstants.odbcDriverNotFoundReason,
          'user_message':
              'The configured ODBC driver was not found on this computer. '
              'Review the driver and data source in settings.',
        },
      );
    }

    if (_isAuthenticationFailure(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Database authentication failed',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'reason': OdbcContextConstants.authenticationFailedReason,
          'user_message':
              'Could not authenticate to the database. '
              'Check username, password, and permissions.',
        },
      );
    }

    if (_isTimeout(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Connection timeout when connecting to database',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'timeout': true,
          'timeout_stage': 'connect',
          // Not directly retryable at RetryManager level; the gateway handles
          // its own reconnect logic for connection timeouts.
          'retryable': false,
          'reason': OdbcContextConstants.connectionTimeoutReason,
          'user_message':
              'The database connection took longer than expected. '
              'Confirm the server is accessible and try again.',
        },
      );
    }

    if (_isServerUnavailable(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Could not reach the database server',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': _isRetryableConnection(sqlState),
          'reason': OdbcContextConstants.serverUnreachableReason,
          'user_message':
              'Could not connect to the database server. '
              'Check host, port, VPN, and network availability.',
        },
      );
    }

    return ConnectionFailure.withContext(
      message: 'Failed to connect to the database',
      cause: error,
      context: {
        ...baseContext,
        'connectionFailed': true,
        'retryable': _isRetryableConnection(sqlState),
        'reason': OdbcContextConstants.databaseConnectionFailedReason,
        'user_message': 'Could not establish a connection to the database.',
      },
    );
  }

  static Failure mapQueryError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final sqlState = _extractSqlState(error);
    final baseContext = _buildBaseContext(error, operation, context);

    if (error is CancelledError) {
      return QueryExecutionFailure.withContext(
        message: 'SQL execution cancelled',
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.executionCancelledReason,
          'rpc_error_code': RpcErrorCode.executionCancelled,
          'user_message': 'The query was cancelled before it finished.',
        },
      );
    }

    if (error is MalformedPayloadError) {
      return QueryExecutionFailure.withContext(
        message: 'Invalid ODBC response',
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.odbcMalformedPayloadReason,
          'user_message': 'The database returned a response that could not be parsed by the agent.',
        },
      );
    }

    if (error is RollbackFailedError) {
      return QueryExecutionFailure.withContext(
        message: 'Failed to roll back transaction',
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.transactionRollbackFailedReason,
          'retryable': error.category == ErrorCategory.transient,
          'user_message': 'The transaction failed and the database did not confirm the rollback.',
        },
      );
    }

    if (error is ResourceLimitReachedError) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.odbcResourceLimitReason,
          'retryable': true,
          'user_message': 'The ODBC resource limit was reached. Try again in a moment.',
        },
      );
    }

    if (error is WorkerCrashedError) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': true,
          'reason': OdbcContextConstants.odbcWorkerCrashedReason,
          'user_message': 'The ODBC worker was interrupted during the query. Try again.',
        },
      );
    }

    if (_isBufferTooSmall(detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.bufferTooSmallReason,
          'user_message':
              'The query result exceeds the current buffer. '
              'Enable streaming or increase the result buffer.',
        },
      );
    }

    if (_isTimeout(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: 'Query execution timeout exceeded',
        cause: error,
        context: {
          ...baseContext,
          'timeout': true,
          'timeout_stage': 'sql',
          'reason': RpcSqlBudgetConstants.queryTimeoutReason,
          'user_message': 'The query took longer than allowed to complete.',
        },
      );
    }

    if (_isConnectionExceptionDuringExecute(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': _isRetryableConnection(sqlState),
          'reason': OdbcContextConstants.connectionLostDuringQueryReason,
          'user_message':
              'The database session was interrupted during the query. '
              'Check the network, server, and try again.',
        },
      );
    }

    if (_isTransientQueryFailure(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'retryable': true,
          'reason': OdbcContextConstants.transientQueryFailureReason,
          'user_message':
              'The database returned a transient failure when executing the query. '
              'Try again.',
        },
      );
    }

    if (_isPermissionDenied(sqlState, detail)) {
      final deniedResources = _extractDeniedResourcesFromPermissionMessage(detail);
      final deniedResourcesForMessage = _formatDeniedResourcesForUserMessage(
        deniedResources,
      );
      final userMessage = deniedResourcesForMessage == null
          ? 'The query was denied due to insufficient permissions in the database.'
          : 'The query was denied due to insufficient permissions for resources: $deniedResourcesForMessage.';
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.sqlPermissionDeniedReason,
          'user_message': userMessage,
          if (deniedResources.isNotEmpty) 'resource': deniedResources.first,
          if (deniedResources.isNotEmpty) 'denied_resources': deniedResources,
        },
      );
    }

    if (_isSyntaxOrValidationError(sqlState, detail) || error is ValidationError) {
      return ValidationFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'operation': 'sql_validation',
          'reason': SqlPipelineContextConstants.sqlValidationFailedReason,
          'user_message':
              'The query could not be executed because it contains a syntax error '
              'or an invalid reference.',
        },
      );
    }

    return QueryExecutionFailure.withContext(
      message: detail,
      cause: error,
      context: {
        ...baseContext,
        'reason': OdbcContextConstants.sqlExecutionFailedReason,
        'user_message': 'The database returned an error when executing the query.',
      },
    );
  }

  static Failure mapPoolError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final baseContext = _buildBaseContext(error, operation, context);
    final isExhausted = error is ResourceLimitReachedError || _isPoolExhausted(detail);
    final contextReason = context['reason']?.toString();
    final contextRetryable = context['retryable'];
    final contextUserMessage = context['user_message']?.toString();

    return ConnectionFailure.withContext(
      message: isExhausted ? 'ODBC connection pool exhausted' : 'Failed to acquire a connection from the ODBC pool',
      cause: error,
      context: {
        ...baseContext,
        'poolExhausted': isExhausted,
        'retryable': contextRetryable is bool ? contextRetryable : isExhausted,
        'reason':
            contextReason ??
            (isExhausted ? OdbcContextConstants.poolExhaustedReason : OdbcContextConstants.poolErrorReason),
        'user_message':
            contextUserMessage ??
            (isExhausted
                ? 'The agent has no free connections available. Try again in a moment.'
                : 'Could not acquire an available ODBC connection.'),
      },
    );
  }

  static Failure mapStreamingError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool cancelledByUser = false,
  }) {
    final baseContext = _buildBaseContext(error, operation, context);

    if (cancelledByUser) {
      return QueryExecutionFailure.withContext(
        message: 'Streaming query cancelled by user',
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.executionCancelledReason,
          'rpc_error_code': RpcErrorCode.executionCancelled,
          'user_message': 'The streaming query was cancelled.',
        },
      );
    }

    return mapQueryError(
      error,
      operation: operation,
      context: {
        ...baseContext,
        'streaming': true,
      },
    );
  }

  static String _extractDetail(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  static String? _extractSqlState(Object error) {
    if (error is! OdbcError) {
      return null;
    }
    final sqlState = error.sqlState?.trim().toUpperCase();
    return (sqlState == null || sqlState.isEmpty) ? null : sqlState;
  }

  static Map<String, dynamic> _buildBaseContext(
    Object error,
    String? operation,
    Map<String, dynamic> context,
  ) {
    final sqlState = _extractSqlState(error);
    final nativeCode = error is OdbcError ? error.nativeCode : null;
    final category = error is OdbcError ? error.category.name : null;

    return {
      ...?(operation != null ? {'operation': operation} : null),
      'odbc_error_type': error.runtimeType.toString(),
      'odbc_message': _extractDetail(error),
      ...?(sqlState != null ? {'odbc_sql_state': sqlState} : null),
      ...?(nativeCode != null ? {'odbc_native_code': nativeCode} : null),
      ...?(category != null ? {'odbc_error_category': category} : null),
      ...context,
    };
  }

  static bool _isDriverMissing(String? sqlState, String detail) {
    // 08xxx = connection/server errors (e.g. 08001 "Database server not found")
    if (sqlState != null && sqlState.startsWith('08')) {
      return false;
    }

    if (sqlState == 'IM002' || sqlState == 'IM003') {
      return true;
    }

    final normalized = detail.toLowerCase();
    // "Database server not found" = server unreachable, not driver missing
    if (normalized.contains('database server not found')) {
      return false;
    }

    return normalized.contains('data source name not found') ||
        normalized.contains('no default driver specified') ||
        (normalized.contains('driver') && normalized.contains('not found')) ||
        normalized.contains("can't open lib") ||
        normalized.contains('library not found');
  }

  static bool _isAuthenticationFailure(String? sqlState, String detail) {
    if (sqlState == '28000') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('login failed') ||
        normalized.contains('authentication failed') ||
        normalized.contains('invalid authorization') ||
        normalized.contains('access denied');
  }

  static bool _isTimeout(String? sqlState, String detail) {
    if (sqlState == 'HYT00' || sqlState == 'HYT01') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('hyt00') ||
        normalized.contains('hyt01');
  }

  static bool _isServerUnavailable(String? sqlState, String detail) {
    if (sqlState != null && sqlState.startsWith('08')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('database server not found') ||
        normalized.contains('server does not exist') ||
        normalized.contains('could not connect') ||
        normalized.contains('network-related') ||
        normalized.contains('connection refused') ||
        normalized.contains('server unavailable') ||
        normalized.contains('unknown host');
  }

  /// SQLSTATE class 08 (connection exception) or equivalent message during execute.
  static bool _isConnectionExceptionDuringExecute(String? sqlState, String detail) {
    if (sqlState != null && sqlState.startsWith('08')) {
      return true;
    }
    final normalized = detail.toLowerCase();
    return normalized.contains('communication link failure') ||
        normalized.contains('connection was terminated') ||
        normalized.contains('connection is no longer usable') ||
        normalized.contains('connection may have been terminated') ||
        (normalized.contains('tcp provider') && normalized.contains('error')) ||
        normalized.contains('broken pipe') ||
        normalized.contains('connection reset');
  }

  static bool _isSyntaxOrValidationError(String? sqlState, String detail) {
    if (sqlState != null &&
        (sqlState.startsWith('42') ||
            sqlState.startsWith('22') ||
            sqlState == '07001' ||
            sqlState == '07002' ||
            sqlState == '07006' ||
            sqlState == '07009' ||
            sqlState == '21S01' ||
            sqlState == '21S02')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('syntax') ||
        normalized.contains('incorrect syntax') ||
        normalized.contains('invalid column') ||
        normalized.contains('invalid object') ||
        normalized.contains('does not exist') ||
        normalized.contains('undeclared');
  }

  static bool _isPermissionDenied(String? sqlState, String detail) {
    if (sqlState == '42501') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('permission denied') ||
        normalized.contains('not authorized') ||
        normalized.contains('insufficient privilege') ||
        normalized.contains('permission was denied');
  }

  static bool _isTransientQueryFailure(String? sqlState, String detail) {
    if (sqlState != null && (sqlState.startsWith('40') || sqlState == 'HY008' || sqlState == 'HY117')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('deadlock') ||
        normalized.contains('serialization failure') ||
        normalized.contains('lock request time out');
  }

  static bool _isPoolExhausted(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains('pool exhausted') ||
        normalized.contains('no connections available') ||
        normalized.contains('all pooled connections are busy');
  }

  static bool _isBufferTooSmall(String detail) {
    return detail.toLowerCase().contains('buffer too small');
  }

  static bool _isRetryableConnection(String? sqlState) {
    return sqlState != null && sqlState.startsWith('08');
  }

  static List<String> _extractDeniedResourcesFromPermissionMessage(String detail) {
    final resources = <String>{};
    for (final match in _sqlServerPermissionObjectPattern.allMatches(detail)) {
      final objectName = _normalizeResourceName(match.group(1));
      final schemaName = _normalizeResourceName(match.group(2));
      if (objectName == null) {
        continue;
      }
      if (schemaName != null && !objectName.contains('.')) {
        resources.add('$schemaName.$objectName');
      } else {
        resources.add(objectName);
      }
    }
    for (final match in _postgresPermissionPattern.allMatches(detail)) {
      final resourceName = _normalizeResourceName(match.group(1));
      if (resourceName != null) {
        resources.add(resourceName);
      }
    }
    for (final match in _quotedResourcePattern.allMatches(detail)) {
      final resourceName = _normalizeResourceName(match.group(1));
      if (resourceName != null) {
        resources.add(resourceName);
      }
    }

    final resourcesWithoutUnqualifiedDuplicates = resources.where((resource) {
      if (resource.contains('.')) {
        return true;
      }
      final qualifiedEquivalentExists = resources.any(
        (candidate) => candidate.contains('.') && candidate.endsWith('.$resource'),
      );
      return !qualifiedEquivalentExists;
    }).toList();
    final sorted = resourcesWithoutUnqualifiedDuplicates..sort();
    return sorted;
  }

  static String? _normalizeResourceName(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().replaceAll('"', '').replaceAll('[', '').replaceAll(']', '');
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String? _formatDeniedResourcesForUserMessage(List<String> resources) {
    if (resources.isEmpty) {
      return null;
    }
    if (resources.length <= _kMaxDeniedResourcesInUserMessage) {
      return resources.join(', ');
    }
    final shown = resources.take(_kMaxDeniedResourcesInUserMessage).join(', ');
    final hiddenCount = resources.length - _kMaxDeniedResourcesInUserMessage;
    return '$shown (+$hiddenCount more)';
  }
}
