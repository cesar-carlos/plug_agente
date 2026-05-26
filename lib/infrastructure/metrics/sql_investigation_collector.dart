import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';

/// Ring buffer of recent SQL investigation events for the dashboard.
class SqlInvestigationCollector implements ISqlInvestigationCollector {
  SqlInvestigationCollector({int maxEvents = AppConstants.dashboardDiagnosticFeedMaxItems}) : _maxEvents = maxEvents;

  final int _maxEvents;

  // ListQueue gives O(1) addFirst/removeLast, replacing the previous O(n)
  // List.insert(0, ...) pattern on the hot RPC denial path.
  final ListQueue<SqlInvestigationEvent> _events = ListQueue<SqlInvestigationEvent>();
  final StreamController<SqlInvestigationEvent> _controller = StreamController<SqlInvestigationEvent>.broadcast();
  final StreamController<void> _revisionController = StreamController<void>.broadcast(sync: true);

  @override
  Stream<SqlInvestigationEvent> get eventsStream => _controller.stream;

  @override
  Stream<void> get feedRevisionStream => _revisionController.stream;

  @override
  List<SqlInvestigationEvent> get events =>
      UnmodifiableListView<SqlInvestigationEvent>(_events.toList(growable: false));

  @override
  void recordAuthorizationDenied({
    required String method,
    required String originalSql,
    String? rpcRequestId,
    String? reason,
    String? clientId,
    String? operation,
    String? resource,
  }) {
    _add(
      SqlInvestigationEvent(
        timestamp: DateTime.now(),
        kind: SqlInvestigationKind.authorizationDenied,
        method: method,
        originalSql: originalSql,
        rpcRequestId: rpcRequestId,
        reason: reason,
        clientId: clientId,
        operation: operation,
        resource: resource,
      ),
    );
  }

  @override
  void recordExecutionFailure({
    required String method,
    required String originalSql,
    required String errorMessage,
    required bool executedInDb,
    required String? effectiveSql,
    String? rpcRequestId,
    String? internalQueryId,
  }) {
    _add(
      SqlInvestigationEvent(
        timestamp: DateTime.now(),
        kind: SqlInvestigationKind.executionError,
        method: method,
        originalSql: originalSql,
        rpcRequestId: rpcRequestId,
        internalQueryId: internalQueryId,
        effectiveSql: effectiveSql,
        errorMessage: errorMessage,
        executedInDb: executedInDb,
      ),
    );
  }

  void _add(SqlInvestigationEvent event) {
    _events.addFirst(event); // O(1)
    while (_events.length > _maxEvents) {
      _events.removeLast(); // O(1)
    }
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  void clear() {
    _events.clear(); // O(1) for ListQueue
    if (!_revisionController.isClosed) {
      _revisionController.add(null);
    }
  }

  @override
  void dispose() {
    _controller.close();
    _revisionController.close();
  }
}
