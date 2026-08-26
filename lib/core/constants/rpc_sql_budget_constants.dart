import 'package:plug_agente/core/constants/odbc_connection_constants.dart';

/// Stable `failure.context['reason']` values for SQL RPC stages when socket
/// stage budgets or merged ODBC timeouts apply (`RpcMethodDispatcher`).
abstract final class RpcSqlBudgetConstants {
  /// Matches [OdbcConnectionConstants.defaultQueryTimeout] so the RPC query
  /// stage can use the full ODBC query window.
  static const Duration defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const Duration defaultQueryStageBudget = OdbcConnectionConstants.defaultQueryTimeout;
  static const Duration defaultSqlExecuteHeadroom = Duration(seconds: 2);

  /// Auth stage + query stage + small headroom for mapping/response.
  static const Duration defaultSqlExecuteTotalBudget = Duration(seconds: 65);
  static const Duration defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const Duration defaultBatchExecutionStageBudget = Duration(seconds: 35);

  static const String authorizationBudgetExhaustedReason = 'authorization_budget_exhausted';

  static const String authorizationTimeoutReason = 'authorization_timeout';

  static const String queryBudgetExhaustedReason = 'query_budget_exhausted';

  /// Used for single-query, batch, and bulk-insert ODBC timeout paths.
  static const String queryTimeoutReason = 'query_timeout';

  static const String batchBudgetExhaustedReason = 'batch_budget_exhausted';

  static const String bulkInsertBudgetExhaustedReason = 'bulk_insert_budget_exhausted';

  static const String materializedResultTooLargeReason = 'materialized_result_too_large';

  static const String playgroundMaterializedUnpaginatedReason = 'playground_materialized_unpaginated';
}
