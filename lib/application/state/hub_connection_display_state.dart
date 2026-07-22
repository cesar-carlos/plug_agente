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

  /// True while app **burst** recovery owns reconnect (`beginManualReconnection`).
  ///
  /// Distinct from [status] == [ConnectionStatus.reconnecting], which is also set
  /// when waiting for Socket.IO L0. Kick/exclusive-recovery gates must use this
  /// flag — not [isReconnectingEffective] — or L0 wait would skip `io_server` kick.
  bool isBurstRecoveryInFlight = false;
  bool isCheckingDriver = false;
  HubRecoveryUiHint hubRecoveryUiHint = HubRecoveryUiHint.none;

  bool get isConnected => status == ConnectionStatus.connected;

  bool get isConnectingOrNegotiating => status == ConnectionStatus.connecting || status == ConnectionStatus.negotiating;

  bool get isReconnectingEffective => isBurstRecoveryInFlight || status == ConnectionStatus.reconnecting;
}
