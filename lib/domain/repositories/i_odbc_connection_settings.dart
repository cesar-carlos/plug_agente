/// Interface para configurações de conexão ODBC (pool, timeouts).
abstract class IOdbcConnectionSettings {
  int get poolSize;
  int get loginTimeoutSeconds;
  int get maxResultBufferMb;
  int get streamingChunkSizeKb;

  /// When true, uses the native `odbc_fast` pool (faster reuse; may hit small
  /// result buffers on pooled handles until fixed upstream). Default false.
  bool get useNativeOdbcPool;
  bool get nativePoolTestOnCheckout;

  Future<void> setPoolSize(int value);
  Future<void> setLoginTimeoutSeconds(int value);
  Future<void> setMaxResultBufferMb(int value);
  Future<void> setStreamingChunkSizeKb(int value);
  Future<void> setUseNativeOdbcPool(bool value);
  Future<void> setNativePoolTestOnCheckout(bool value);
  Future<void> load();
}
