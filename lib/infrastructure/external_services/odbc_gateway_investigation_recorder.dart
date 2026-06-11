import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';

/// Records SQL investigation feed events for batch and gateway-level failures.
class OdbcGatewayInvestigationRecorder {
  OdbcGatewayInvestigationRecorder({
    FeatureFlags? featureFlags,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _featureFlags = featureFlags,
       _sqlInvestigation = sqlInvestigation;

  final FeatureFlags? _featureFlags;
  final ISqlInvestigationCollector? _sqlInvestigation;

  bool get _enabled => _featureFlags?.enableDashboardSqlInvestigationFeed ?? true;

  void recordExecutionFailure({
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String errorMessage,
    required bool executedInDb,
    String method = 'sql.execute',
  }) {
    if (!_enabled) {
      return;
    }
    final inv = _sqlInvestigation;
    if (inv == null) {
      return;
    }
    final original = request.query;
    final effective = preparedExecution.sql;
    final effectiveForUi = original.trim() == effective.trim() ? null : effective;
    inv.recordExecutionFailure(
      method: method,
      originalSql: original,
      errorMessage: errorMessage,
      executedInDb: executedInDb,
      effectiveSql: effectiveForUi,
      rpcRequestId: request.sourceRpcRequestId,
      internalQueryId: request.id,
    );
  }

  void recordBatchInfrastructureFailure({
    required String originalSql,
    required String errorMessage,
    String? rpcRequestId,
    String method = 'sql.executeBatch',
  }) {
    if (!_enabled) {
      return;
    }
    final inv = _sqlInvestigation;
    if (inv == null) {
      return;
    }
    inv.recordExecutionFailure(
      method: method,
      originalSql: originalSql.isEmpty ? '(sql.executeBatch)' : originalSql,
      errorMessage: errorMessage,
      executedInDb: false,
      effectiveSql: null,
      rpcRequestId: rpcRequestId,
    );
  }
}
