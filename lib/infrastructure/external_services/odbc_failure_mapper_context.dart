import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';

/// Shared ODBC error detail extraction and failure context assembly.
class OdbcFailureMapperContext {
  OdbcFailureMapperContext._();

  static String extractDetail(Object error) {
    final structured = OdbcErrorInspector.structuredError(error);
    if (structured != null) return structured.message;
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  static String? extractSqlState(Object error) {
    final sqlState = OdbcErrorInspector.sqlState(error)?.trim().toUpperCase();
    return (sqlState == null || sqlState.isEmpty) ? null : sqlState;
  }

  static Map<String, dynamic> buildBaseContext(
    Object error,
    String? operation,
    Map<String, dynamic> context,
  ) {
    final sqlState = extractSqlState(error);
    final structured = OdbcErrorInspector.structuredError(error);
    final details = structured?.details;
    final nativeCode = structured?.nativeCode;
    final category = structured?.category.name;

    return {
      if (error is domain.Failure) ...error.context,
      ...?(operation != null ? {'operation': operation} : null),
      'odbc_error_type': error.runtimeType.toString(),
      'odbc_message': extractDetail(error),
      ...?(sqlState != null ? {'odbc_sql_state': sqlState} : null),
      ...?(nativeCode != null ? {'odbc_native_code': nativeCode} : null),
      ...?(category != null ? {'odbc_error_category': category} : null),
      ...context,
      if (structured != null) 'odbc_error_code': structured.code.name,
      if (details?.operation != null) 'odbc_operation': details!.operation,
      if (details?.connectionId != null) 'odbc_connection_id': details!.connectionId,
      if (details?.transactionId != null) 'odbc_transaction_id': details!.transactionId,
      if (details?.requestId != null) 'odbc_request_id': details!.requestId,
      if (details?.workerId != null) 'odbc_worker_id': details!.workerId,
      if (details?.attempt != null) 'odbc_attempt': details!.attempt,
      if (details?.stackTrace != null) 'odbc_stack_trace': details!.stackTrace.toString(),
      if (details != null && details.secondaryErrors.isNotEmpty)
        'secondary_errors': details.secondaryErrors.map(safeSecondary).toList(growable: false),
      if (OdbcErrorInspector.outcomeUnknown(error)) ...{
        'outcome_unknown': true,
        'retryable': false,
      },
    };
  }

  static Map<String, Object?> safeSecondary(OdbcError error) => {
    'odbc_error_code': error.code.name,
    'odbc_operation': error.details.operation,
    'outcome_unknown': error.details.outcomeUnknown,
    'odbc_sql_state': error.sqlState,
    'odbc_native_code': error.nativeCode,
  };
}
