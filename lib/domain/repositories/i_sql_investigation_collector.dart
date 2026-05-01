import 'package:plug_agente/domain/entities/sql_investigation_event.dart';

/// In-memory feed of SQL authorization and execution failures for diagnostics UIs.
abstract class ISqlInvestigationCollector {
  Stream<SqlInvestigationEvent> get eventsStream;

  /// Fires when [clear] empties the buffer (e.g. ODBC runtime reload).
  Stream<void> get feedRevisionStream;

  List<SqlInvestigationEvent> get events;

  void recordAuthorizationDenied({
    required String method,
    required String originalSql,
    String? rpcRequestId,
    String? reason,
    String? clientId,
    String? operation,
    String? resource,
  });

  void recordExecutionFailure({
    required String method,
    required String originalSql,
    required String errorMessage,
    required bool executedInDb,
    required String? effectiveSql,
    String? rpcRequestId,
    String? internalQueryId,
  });

  void clear();

  void dispose();
}
