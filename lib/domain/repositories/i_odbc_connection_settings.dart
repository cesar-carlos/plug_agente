/// Interface para configurações de conexão ODBC (pool, timeouts).
abstract class IOdbcConnectionSettings {
  int get poolSize;
  int get loginTimeoutSeconds;
  int get maxResultBufferMb;
  int get streamingChunkSizeKb;

  Future<void> setPoolSize(int value);
  Future<void> setLoginTimeoutSeconds(int value);
  Future<void> setMaxResultBufferMb(int value);
  Future<void> setStreamingChunkSizeKb(int value);
  Future<void> load();
}
