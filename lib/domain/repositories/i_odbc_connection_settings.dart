/// Interface para configurações de conexão ODBC (pool, timeouts).
abstract class IOdbcConnectionSettings {
  int get poolSize;
  int get loginTimeoutSeconds;
  int get maxResultBufferMb;
  int get streamingChunkSizeKb;

  /// When true, uses the native `odbc_fast` pool (faster reuse; may hit small
  /// result buffers on pooled handles until fixed upstream). Default false.
  bool get useNativeOdbcPool;

  /// Seconds to keep released lease connections idle for reuse; `0` disables.
  int get leaseIdleTtlSeconds;

  /// Target idle leases to pre-open per DSN (lease pool only); `0` disables.
  int get leaseWarmupCount;

  Future<void> setPoolSize(int value);
  Future<void> setLoginTimeoutSeconds(int value);
  Future<void> setMaxResultBufferMb(int value);
  Future<void> setStreamingChunkSizeKb(int value);
  Future<void> setUseNativeOdbcPool(bool value);
  Future<void> setLeaseIdleTtlSeconds(int value);
  Future<void> setLeaseWarmupCount(int value);
  Future<void> load();
}
