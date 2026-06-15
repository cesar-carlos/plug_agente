/// Controls whether plug_agente maintains a per-connection Dart LRU prepare
/// cache in addition to the native pool cache inside `odbc_fast` 4.2+.
enum OdbcPreparedStatementCachePolicy {
  /// Lease-pool and SQL Anywhere paths keep the Dart LRU prepare cache.
  leasePool(dartLruEnabled: true),

  /// Native-compatible pool routes rely on the driver/native prepared cache.
  nativePool(dartLruEnabled: false);

  const OdbcPreparedStatementCachePolicy({required this.dartLruEnabled});

  final bool dartLruEnabled;

  static OdbcPreparedStatementCachePolicy forExecutionMode(String executionMode) {
    return executionMode == 'native_compatible' ? nativePool : leasePool;
  }
}
