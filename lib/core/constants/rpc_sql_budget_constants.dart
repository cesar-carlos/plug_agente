/// Stable `failure.context['reason']` values for SQL RPC stages when socket
/// stage budgets or merged ODBC timeouts apply (`RpcMethodDispatcher`).
abstract final class RpcSqlBudgetConstants {
  static const String authorizationBudgetExhaustedReason = 'authorization_budget_exhausted';

  static const String authorizationTimeoutReason = 'authorization_timeout';

  static const String queryBudgetExhaustedReason = 'query_budget_exhausted';

  /// Used for single-query, batch, and bulk-insert ODBC timeout paths.
  static const String queryTimeoutReason = 'query_timeout';

  static const String batchBudgetExhaustedReason = 'batch_budget_exhausted';

  static const String bulkInsertBudgetExhaustedReason = 'bulk_insert_budget_exhausted';
}
