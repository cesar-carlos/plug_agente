import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';

class ResolvedSqlHandlingMode {
  const ResolvedSqlHandlingMode({
    this.sqlHandlingMode,
    this.errorMessage,
  });

  final SqlHandlingMode? sqlHandlingMode;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

int resolveRequestedTimeoutMs(Map<String, dynamic> params) {
  final options = params['options'] as Map<String, dynamic>?;
  return jsonPositiveInt(options?['timeout_ms']) ?? 0;
}

int resolveMaxRows(Map<String, dynamic> params, int negotiatedMaxRows) {
  final options = params['options'] as Map<String, dynamic>?;
  final requestedMaxRows = jsonPositiveInt(options?['max_rows']);
  if (requestedMaxRows == null) {
    return negotiatedMaxRows;
  }
  return requestedMaxRows < negotiatedMaxRows ? requestedMaxRows : negotiatedMaxRows;
}

bool resolveMultiResult(Map<String, dynamic> params) {
  final options = params['options'] as Map<String, dynamic>?;
  return options?['multi_result'] == true;
}

ResolvedSqlHandlingMode resolveSqlHandlingMode(
  Map<String, dynamic> params,
) {
  final options = params['options'] as Map<String, dynamic>?;
  if (options == null) {
    return const ResolvedSqlHandlingMode(
      sqlHandlingMode: SqlHandlingMode.managed,
    );
  }

  final executionMode = options['execution_mode'];
  if (executionMode != null && executionMode is! String) {
    return const ResolvedSqlHandlingMode(
      errorMessage: 'execution_mode must be a string',
    );
  }
  if (executionMode != null && executionMode != 'managed' && executionMode != 'preserve') {
    return const ResolvedSqlHandlingMode(
      errorMessage: 'execution_mode must be "managed" or "preserve"',
    );
  }

  final preserveSql = options['preserve_sql'];
  if (preserveSql != null && preserveSql is! bool) {
    return const ResolvedSqlHandlingMode(
      errorMessage: 'preserve_sql must be a boolean',
    );
  }
  if (preserveSql == true && executionMode == 'managed') {
    return const ResolvedSqlHandlingMode(
      errorMessage: 'preserve_sql cannot be true when execution_mode is "managed"',
    );
  }

  if (preserveSql == true) {
    AppLogger.warning(
      'options.preserve_sql is deprecated; use options.execution_mode: '
      '"preserve" instead',
    );
  }

  final resolvedMode = executionMode == 'preserve' || preserveSql == true
      ? SqlHandlingMode.preserve
      : SqlHandlingMode.managed;
  final hasManagedPagination = options['page'] != null || options['page_size'] != null || options['cursor'] != null;
  if (resolvedMode == SqlHandlingMode.preserve && hasManagedPagination) {
    return const ResolvedSqlHandlingMode(
      errorMessage: 'execution_mode "preserve" cannot be combined with page, page_size, or cursor',
    );
  }

  return ResolvedSqlHandlingMode(sqlHandlingMode: resolvedMode);
}
