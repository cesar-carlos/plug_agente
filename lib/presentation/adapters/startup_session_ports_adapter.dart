import 'package:plug_agente/application/ports/i_startup_session_auth_sink.dart';
import 'package:plug_agente/application/ports/i_startup_session_config_source.dart';
import 'package:plug_agente/application/ports/i_startup_session_connection_gateway.dart';
import 'package:plug_agente/application/ports/startup_session_ports.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:result_dart/result_dart.dart';

class StartupSessionConfigAdapter implements IStartupSessionConfigSource {
  StartupSessionConfigAdapter(this._configProvider);

  final ConfigProvider _configProvider;

  @override
  bool get isLoading => _configProvider.isLoading;

  @override
  Config? get currentConfig => _configProvider.currentConfig;
}

class StartupSessionAuthAdapter implements IStartupSessionAuthSink {
  StartupSessionAuthAdapter(this._authProvider);

  final AuthProvider _authProvider;

  @override
  void restoreToken(
    AuthToken token, {
    String? configId,
    bool silent = false,
  }) {
    _authProvider.restoreToken(token, configId: configId, silent: silent);
  }

  @override
  void setRecoveryError(String message) {
    _authProvider.setRecoveryError(message);
  }
}

class StartupSessionConnectionAdapter implements IStartupSessionConnectionGateway {
  StartupSessionConnectionAdapter(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  @override
  bool get isConnected => _connectionProvider.isConnected;

  @override
  ConnectionStatus get status => _connectionProvider.status;

  @override
  bool get isReconnecting => _connectionProvider.isReconnecting;

  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) {
    return _connectionProvider.connect(
      serverUrl,
      agentId,
      configId: configId,
      authToken: authToken,
      recoverOnFailure: recoverOnFailure,
    );
  }

  @override
  void startPersistentHubRecovery({
    required String configId,
    required String serverUrl,
    required String agentId,
  }) {
    _connectionProvider.startPersistentHubRecovery(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
    );
  }
}

StartupSessionPorts startupSessionPortsFromProviders({
  required ConfigProvider configProvider,
  required AuthProvider authProvider,
  required ConnectionProvider connectionProvider,
}) {
  return StartupSessionPorts(
    config: StartupSessionConfigAdapter(configProvider),
    auth: StartupSessionAuthAdapter(authProvider),
    connection: StartupSessionConnectionAdapter(connectionProvider),
  );
}
