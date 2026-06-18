import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:result_dart/result_dart.dart';

/// Hub connection operations for startup auto-session flows.
abstract interface class IStartupSessionConnectionGateway {
  bool get isConnected;

  ConnectionStatus get status;

  bool get isReconnecting;

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  });

  void startPersistentHubRecovery({
    required String configId,
    required String serverUrl,
    required String agentId,
  });
}
