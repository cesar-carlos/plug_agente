import 'package:get_it/get_it.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/rpc/sql_streaming_connection_string_cache.dart';
import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/domain/repositories/i_odbc_application_runtime_reset_port.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';

final class OdbcApplicationRuntimeResetService implements IOdbcApplicationRuntimeResetPort {
  OdbcApplicationRuntimeResetService({required GetIt getIt}) : _getIt = getIt;

  final GetIt _getIt;

  @override
  Future<void> resetForOdbcRuntimeReload() async {
    _invalidateActiveConfigCaches();
    await _resetLazySingletonIfRegistered<RpcMethodDispatcher>();
    await _resetLazySingletonIfRegistered<SqlExecutionQueue>();
  }

  void _invalidateActiveConfigCaches() {
    if (_getIt.isRegistered<ActiveConfigMetadataCache>()) {
      _getIt<ActiveConfigMetadataCache>().invalidate();
    }
    if (_getIt.isRegistered<SqlStreamingConnectionStringCache>()) {
      _getIt<SqlStreamingConnectionStringCache>().invalidate();
    }
    if (_getIt.isRegistered<IOdbcStreamingSessionCache>()) {
      _getIt<IOdbcStreamingSessionCache>().invalidate();
    }
  }

  Future<void> _resetLazySingletonIfRegistered<T extends Object>() async {
    if (!_getIt.isRegistered<T>()) {
      return;
    }
    await _getIt.resetLazySingleton<T>();
  }
}
