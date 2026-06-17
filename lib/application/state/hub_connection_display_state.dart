import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  negotiating,
  connected,
  reconnecting,
  error,
}

/// Mutable hub connection indicators shared between coordination and presentation.
final class HubConnectionDisplayState {
  ConnectionStatus status = ConnectionStatus.disconnected;
  String error = '';
  bool isDbConnected = false;
  bool isReconnecting = false;
  bool isCheckingDriver = false;
  HubRecoveryUiHint hubRecoveryUiHint = HubRecoveryUiHint.none;

  bool get isConnected => status == ConnectionStatus.connected;

  bool get isConnectingOrNegotiating =>
      status == ConnectionStatus.connecting || status == ConnectionStatus.negotiating;

  bool get isReconnectingEffective => isReconnecting || status == ConnectionStatus.reconnecting;
}
