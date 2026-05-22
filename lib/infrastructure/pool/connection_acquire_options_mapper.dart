import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';

extension ConnectionAcquireOptionsMapper on ConnectionAcquireOptions {
  odbc.ConnectionOptions toOdbcConnectionOptions() {
    return odbc.ConnectionOptions(
      loginTimeout: loginTimeout,
      queryTimeout: queryTimeout,
      maxResultBufferBytes: maxResultBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: autoReconnectOnConnectionLost ?? false,
      maxReconnectAttempts: maxReconnectAttempts,
      reconnectBackoff: reconnectBackoff,
    );
  }
}
