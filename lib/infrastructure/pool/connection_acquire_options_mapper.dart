import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';

extension ConnectionAcquireOptionsMapper on ConnectionAcquireOptions {
  odbc.ConnectionOptions toOdbcConnectionOptions({
    odbc.ConnectionOptions? recommendedProfile,
    bool lazyStrings = false,
  }) {
    if (recommendedProfile == null) {
      return odbc.ConnectionOptions(
        loginTimeout: loginTimeout,
        queryTimeout: queryTimeout,
        maxResultBufferBytes: maxResultBufferBytes,
        initialResultBufferBytes: initialResultBufferBytes,
        autoReconnectOnConnectionLost: autoReconnectOnConnectionLost ?? false,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectBackoff: reconnectBackoff,
        lazyStrings: lazyStrings,
      );
    }

    return OdbcRecommendedOptionsMerger.mergeConnectionOptions(
      plugOptions: this,
      recommended: recommendedProfile,
      lazyStrings: lazyStrings,
    );
  }
}
