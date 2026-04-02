import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

class MockOdbcConnectionSettings implements IOdbcConnectionSettings {
  MockOdbcConnectionSettings({
    this.poolSize = 4,
    this.loginTimeoutSeconds = 30,
    this.maxResultBufferMb = 32,
    this.streamingChunkSizeKb = 1024,
    this.useNativeOdbcPool = false,
  });

  @override
  int poolSize;

  @override
  int loginTimeoutSeconds;

  @override
  int maxResultBufferMb;

  @override
  int streamingChunkSizeKb;

  @override
  bool useNativeOdbcPool;

  @override
  Future<void> load() async {}

  @override
  Future<void> setPoolSize(int value) async => poolSize = value;

  @override
  Future<void> setLoginTimeoutSeconds(int value) async => loginTimeoutSeconds = value;

  @override
  Future<void> setMaxResultBufferMb(int value) async => maxResultBufferMb = value;

  @override
  Future<void> setStreamingChunkSizeKb(int value) async => streamingChunkSizeKb = value;

  @override
  Future<void> setUseNativeOdbcPool(bool value) async => useNativeOdbcPool = value;
}
