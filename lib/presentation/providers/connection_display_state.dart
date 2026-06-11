import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:plug_agente/presentation/presentation.dart' show ConnectionProvider;
import 'package:plug_agente/presentation/providers/connection_provider.dart' show ConnectionProvider;
import 'package:plug_agente/presentation/providers/providers.dart' show ConnectionProvider;

enum ConnectionStatus {
  disconnected,
  connecting,
  negotiating,
  connected,
  reconnecting,
  error,
}

/// Mutable hub/DB connection indicators consumed by [ConnectionProvider] widgets.
final class ConnectionDisplayState {
  ConnectionStatus status = ConnectionStatus.disconnected;
  String error = '';
  bool isDbConnected = false;
  bool isReconnecting = false;
  bool isCheckingDriver = false;
  HubRecoveryUiHint hubRecoveryUiHint = HubRecoveryUiHint.none;

  bool get isConnected => status == ConnectionStatus.connected;

  bool get isConnectingOrNegotiating => status == ConnectionStatus.connecting || status == ConnectionStatus.negotiating;

  bool get isReconnectingEffective => isReconnecting || status == ConnectionStatus.reconnecting;
}
