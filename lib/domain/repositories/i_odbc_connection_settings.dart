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

  /// `null` leaves checkout session reset at the odbc_fast default (`true`).
  /// Checkin reset stays unconditional either way.
  bool? get nativePoolSessionResetOnCheckout;

  Future<void> setPoolSize(int value);
  Future<void> setLoginTimeoutSeconds(int value);
  Future<void> setMaxResultBufferMb(int value);
  Future<void> setStreamingChunkSizeKb(int value);
  Future<void> setUseNativeOdbcPool(bool value);
  Future<void> setNativePoolTestOnCheckout(bool value);
  Future<void> setNativePoolSessionResetOnCheckout(bool? value);
  Future<void> load();
}
