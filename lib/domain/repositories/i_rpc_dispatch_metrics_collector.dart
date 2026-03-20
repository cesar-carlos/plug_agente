/// Optional counters for RPC `sql.execute` result paths (observability).
abstract class IRpcDispatchMetricsCollector {
  void recordSqlExecuteStreamingChunksResponse();

  void recordSqlExecuteStreamingFromDbResponse();

  void recordSqlExecuteMaterializedResponse();
}
