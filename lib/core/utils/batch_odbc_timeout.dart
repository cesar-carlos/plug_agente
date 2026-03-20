/// Merges stage-derived ODBC timeout with RPC `options.timeout_ms` (client cap).
///
/// When [stageTimeout] is null (socket stage timeouts disabled), returns null so
/// callers keep prior "no Dart-side cap" behaviour for the batch.
///
/// [timeoutMs] <= 0 means no client cap: [stageTimeout] is returned unchanged.
Duration? mergeBatchOdbcTimeout({
  required Duration? stageTimeout,
  required int timeoutMs,
}) {
  if (timeoutMs <= 0) {
    return stageTimeout;
  }
  final client = Duration(milliseconds: timeoutMs);
  if (stageTimeout == null) {
    return null;
  }
  return stageTimeout < client ? stageTimeout : client;
}
