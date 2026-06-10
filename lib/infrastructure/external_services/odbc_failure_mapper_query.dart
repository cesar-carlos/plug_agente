import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_connection.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_context.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_timeout.dart';

/// Maps ODBC query execution errors to typed [Failure] values.
class OdbcFailureMapperQuery {
  OdbcFailureMapperQuery._();

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

  static Failure map(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = OdbcFailureMapperContext.extractDetail(error);
    final sqlState = OdbcFailureMapperContext.extractSqlState(error);
    final baseContext = OdbcFailureMapperContext.buildBaseContext(error, operation, context);

    if (error is CancelledError || error is CancellationException) {
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

    if (OdbcFailureMapperTimeout.isTimeout(sqlState, detail)) {
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

    if (OdbcFailureMapperConnection.isConnectionExceptionDuringExecute(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': OdbcFailureMapperConnection.isRetryableConnection(sqlState),
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

    // The driver's own categorization is a robust last-resort signal when the
    // SQLSTATE/message heuristics above did not match. It only refines the
    // otherwise-flat generic failure, so the richer branches (permission,
    // buffer, timeout, connection-lost) keep precedence and their context.
    final categorized = _mapByErrorCategory(error, detail, baseContext);
    if (categorized != null) {
      return categorized;
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

  /// Refines a query failure from the driver-provided [OdbcError.category] when
  /// the specific heuristics did not classify it. Returns null for non-ODBC
  /// errors and for [ErrorCategory.fatal] (handled by the generic fallback).
  static Failure? _mapByErrorCategory(
    Object error,
    String detail,
    Map<String, dynamic> baseContext,
  ) {
    if (error is! OdbcError) {
      return null;
    }
    switch (error.category) {
      case ErrorCategory.connectionLost:
        return QueryExecutionFailure.withContext(
          message: detail,
          cause: error,
          context: {
            ...baseContext,
            'connectionFailed': true,
            'retryable': error.isRetryable,
            'reason': OdbcContextConstants.connectionLostDuringQueryReason,
            'user_message':
                'The database session was interrupted during the query. '
                'Check the network, server, and try again.',
          },
        );
      case ErrorCategory.transient:
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
      case ErrorCategory.validation:
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
      case ErrorCategory.fatal:
        return null;
    }
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
    if (normalized.contains('syntax') ||
        normalized.contains('incorrect syntax') ||
        normalized.contains('invalid column') ||
        normalized.contains('invalid object') ||
        normalized.contains('undeclared')) {
      return true;
    }

    // "does not exist" usually means a missing relation/column/object reference
    // (a query validation error). A missing database/catalog, however, is a
    // configuration/connection concern, not a query the user can fix by editing
    // SQL — so only treat the object-scoped phrasing as a validation error.
    if (normalized.contains('does not exist')) {
      final isObjectScope = normalized.contains('relation') ||
          normalized.contains('table') ||
          normalized.contains('column') ||
          normalized.contains('function') ||
          normalized.contains('view') ||
          normalized.contains('object') ||
          normalized.contains('schema');
      final isCatalogScope = normalized.contains('database') || normalized.contains('catalog');
      return isObjectScope || !isCatalogScope;
    }

    return false;
  }

  static bool _isPermissionDenied(String? sqlState, String detail) {
    if (sqlState == '42501') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('permission denied') ||
        normalized.contains('not authorized') ||
        normalized.contains('insufficient privilege') ||
        normalized.contains('permission was denied') ||
        // Execute-time "access denied"/"command denied" (e.g. MySQL) is a
        // privilege problem on the object, not a connect-time auth failure.
        normalized.contains('access denied') ||
        normalized.contains('command denied');
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

  static bool _isBufferTooSmall(String detail) {
    return detail.toLowerCase().contains('buffer too small');
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
