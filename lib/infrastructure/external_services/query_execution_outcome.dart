import 'package:plug_agente/domain/entities/query_response.dart';

/// Result of a single ODBC query/command execution attempt: either a built
/// [QueryResponse] or the [error] that prevented it.
///
/// Shared between the gateway orchestration and the execution runners so the
/// runner layer can be extracted without leaking a private type.
class QueryExecutionOutcome {
  const QueryExecutionOutcome.success(this.response) : error = null;

  const QueryExecutionOutcome.failure(this.error) : response = null;

  final QueryResponse? response;
  final Object? error;

  bool get isSuccess => response != null;
}
