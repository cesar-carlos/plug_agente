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

    final handles = _registry.peekAll(requestId);
    if (handles.isEmpty) {
      if (armIfMissing) {
        _registry.markPendingAbort(requestId);
      }
      return const Success(false);
    }

    return _abortHandles(requestId, handles);
  }

  void _onPendingAbortReady(String requestId) {
    unawaited(_fulfillPendingAbort(requestId));
  }

  Future<void> _fulfillPendingAbort(String requestId) async {
    if (!_registry.hasPendingAbort(requestId) && !_registry.hasOwnerAbort(requestId)) {
      return;
    }

    final handles = _registry.peekAll(requestId);
    if (handles.isEmpty) {
      return;
    }

    await _abortHandles(requestId, handles);
  }

  Future<Result<bool>> _abortHandles(
    String requestId,
    List<OdbcInFlightExecutionHandle> handles,
  ) async {
    var hasPendingTarget = false;
    for (final handle in handles) {
      if (handle.hasNativeCancelTarget) {
        await _statementExecutor.abortInFlightHandle(handle);
        continue;
      }

      // Keep pending until bind provides a native cancel target. This is per
      // owner so later parallel children are also cancelled.
      hasPendingTarget = true;
      _markConnectionForDiscard?.call(handle.connectionId);
    }

    // Keep the owner armed until its final child unregisters. A parallel batch
    // can register the next child after every current handle already has a
    // native target; clearing here would let that child escape cancellation.
    _registry.markOwnerAbort(requestId);
    if (hasPendingTarget) {
      _registry.markPendingAbort(requestId);
      developer.log(
        'In-flight abort is waiting for a native cancel target; affected connections are quarantined',
        name: 'database_gateway',
        level: 900,
        error: <String, Object?>{'request_id': requestId, 'handle_count': handles.length},
      );
    } else {
      // The pre-registration ghost race has been fulfilled. The owner remains
      // armed separately so later parallel children still observe cancellation.
      _registry.clearPendingAbort(requestId);
    }

    return const Success(true);
  }
}
