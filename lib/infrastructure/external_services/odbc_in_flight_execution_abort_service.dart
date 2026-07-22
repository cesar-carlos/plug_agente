import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:result_dart/result_dart.dart';

/// Aborts registered in-flight ODBC executions via native cancel APIs.
///
/// Ghost-path callers pass `armIfMissing: true` so abort requested before
/// register is fulfilled on register/bind. Unknown `sql.cancel` misses must
/// not arm pending (avoids poison-pill cancels of later work).
///
/// When a handle is registered but has no native cancel target yet, abort marks
/// the connection for discard and keeps pending until bindStatement /
/// bindAsyncRequest provides a real ODBC cancel handle.
final class OdbcInFlightExecutionAbortService implements ISqlInFlightExecutionAbortPort {
  OdbcInFlightExecutionAbortService({
    required OdbcInFlightExecutionRegistry registry,
    required OdbcStatementExecutor statementExecutor,
    void Function(String connectionId)? markConnectionForDiscard,
  }) : _registry = registry,
       _statementExecutor = statementExecutor,
       _markConnectionForDiscard = markConnectionForDiscard {
    _registry.setPendingAbortListener(_onPendingAbortReady);
  }

  final OdbcInFlightExecutionRegistry _registry;
  final OdbcStatementExecutor _statementExecutor;
  final void Function(String connectionId)? _markConnectionForDiscard;

  @override
  Future<Result<bool>> abortInFlightExecution(
    String requestId, {
    bool armIfMissing = false,
  }) async {
    if (requestId.isEmpty) {
      return const Success(false);
    }

    final handle = _registry.peek(requestId);
    if (handle == null) {
      if (armIfMissing) {
        _registry.markPendingAbort(requestId);
      }
      return const Success(false);
    }

    return _abortHandle(requestId, handle);
  }

  void _onPendingAbortReady(String requestId) {
    unawaited(_fulfillPendingAbort(requestId));
  }

  Future<void> _fulfillPendingAbort(String requestId) async {
    if (!_registry.hasPendingAbort(requestId)) {
      return;
    }

    final handle = _registry.peek(requestId);
    if (handle == null) {
      return;
    }

    await _abortHandle(requestId, handle);
  }

  Future<Result<bool>> _abortHandle(
    String requestId,
    OdbcInFlightExecutionHandle handle,
  ) async {
    if (handle.hasNativeCancelTarget) {
      await _statementExecutor.abortInFlightHandle(handle);
      _registry.clearPendingAbort(requestId);
    } else {
      // Keep pending until bind provides a native cancel target.
      _registry.markPendingAbort(requestId);
      _markConnectionForDiscard?.call(handle.connectionId);
      developer.log(
        'In-flight abort had no native cancel target; connection marked for discard when available',
        name: 'database_gateway',
        level: 900,
        error: {'request_id': requestId, 'connection_id': handle.connectionId},
      );
    }

    return const Success(true);
  }
}
