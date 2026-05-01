/// Merges stage-derived ODBC timeout with RPC `options.timeout_ms` (client cap).
///
/// [timeoutMs] <= 0 means no client cap: [stageTimeout] is returned unchanged.
Duration? mergeOdbcTimeout({
  required Duration? stageTimeout,
  required int timeoutMs,
}) {
  if (timeoutMs <= 0) {
    return stageTimeout;
  }
  final client = Duration(milliseconds: timeoutMs);
  if (stageTimeout == null) {
    return client;
  }
  return stageTimeout < client ? stageTimeout : client;
}

/// Backwards-compatible alias kept for batch call sites and tests.
Duration? mergeBatchOdbcTimeout({
  required Duration? stageTimeout,
  required int timeoutMs,
}) {
  return mergeOdbcTimeout(
    stageTimeout: stageTimeout,
    timeoutMs: timeoutMs,
  );
}
