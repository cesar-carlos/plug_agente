/// SQL execution lane used by the bounded SQL execution queue.
enum SqlExecutionKind {
  /// Generic kind — treated identically to `shortQuery`. Used as the default
  /// for callers that do not classify the request outside QueuedDatabaseGateway.
  query,
  shortQuery,
  longQuery,
  nonQuery,
  batch,

  /// ODBC streaming execution — shares the global worker pool with SQL queue.
  streaming,
}
