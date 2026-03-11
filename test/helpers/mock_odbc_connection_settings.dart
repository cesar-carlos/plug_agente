import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

class MockOdbcConnectionSettings implements IOdbcConnectionSettings {
  MockOdbcConnectionSettings({
    this.poolSize = 4,
    this.loginTimeoutSeconds = 30,
    this.maxResultBufferMb = 32,
  });

  @override
  int poolSize;

  @override
  int loginTimeoutSeconds;

  @override
  int maxResultBufferMb;

  @override
  Future<void> load() async {}

  @override
  Future<void> setPoolSize(int value) async => poolSize = value;

  @override
  Future<void> setLoginTimeoutSeconds(int value) async =>
      loginTimeoutSeconds = value;

  @override
  Future<void> setMaxResultBufferMb(int value) async =>
      maxResultBufferMb = value;
}
