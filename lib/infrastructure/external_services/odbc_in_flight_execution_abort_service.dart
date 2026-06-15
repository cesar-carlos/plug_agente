import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:result_dart/result_dart.dart';

/// Aborts registered in-flight ODBC executions via native cancel APIs.
final class OdbcInFlightExecutionAbortService implements ISqlInFlightExecutionAbortPort {
  OdbcInFlightExecutionAbortService({
    required OdbcInFlightExecutionRegistry registry,
    required OdbcStatementExecutor statementExecutor,
    void Function(String connectionId)? markConnectionForDiscard,
  }) : _registry = registry,
       _statementExecutor = statementExecutor,
       _markConnectionForDiscard = markConnectionForDiscard;

  final OdbcInFlightExecutionRegistry _registry;
  final OdbcStatementExecutor _statementExecutor;
  final void Function(String connectionId)? _markConnectionForDiscard;

  @override
  Future<Result<void>> abortInFlightExecution(String requestId) async {
    if (requestId.isEmpty) {
      return const Success(unit);
    }

    final handle = _registry.peek(requestId);
    if (handle == null) {
      return const Success(unit);
    }

    if (handle.hasNativeCancelTarget) {
      await _statementExecutor.abortInFlightHandle(handle);
    } else {
      _markConnectionForDiscard?.call(handle.connectionId);
      developer.log(
        'In-flight abort had no native cancel target; connection marked for discard when available',
        name: 'database_gateway',
        level: 900,
        error: {'request_id': requestId, 'connection_id': handle.connectionId},
      );
    }

    return const Success(unit);
  }
}
