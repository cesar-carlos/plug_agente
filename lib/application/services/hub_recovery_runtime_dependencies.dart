import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Callbacks and services required by hub recovery orchestration without coupling
/// to Flutter or presentation-layer state objects.
final class HubRecoveryRuntimeDependencies {
  HubRecoveryRuntimeDependencies({
    required this.resilienceCoordinator,
    required this.contextSource,
    required this.checkHubAvailability,
    required this.uiSink,
    required this.resilienceLogPrefix,
    required this.isDisconnectRequested,
    required this.tryRefreshToken,
    required this.attemptReconnect,
    required this.disconnectTransportForRecovery,
    required this.executeHardRelogin,
    required this.bumpPersistentReconnectFailure,
    required this.isStatusError,
    required this.cancelPersistentRetryTimer,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final IConnectionContextSource contextSource;
  final CheckHubAvailability? checkHubAvailability;
  final HubRecoveryUiSink uiSink;
  final String Function() resilienceLogPrefix;
  final bool Function() isDisconnectRequested;
  final Future<TokenRefreshResult> Function(HubConnectionContext context) tryRefreshToken;
  final Future<bool> Function(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage,
  })
  attemptReconnect;
  final Future<void> Function() disconnectTransportForRecovery;
  final Future<String?> Function(
    HubConnectionContext context, {
    required String logSummary,
    bool ignoreCooldown,
  })
  executeHardRelogin;
  final void Function(HubConnectionContext context, {required String reason}) bumpPersistentReconnectFailure;
  final bool Function() isStatusError;
  final void Function() cancelPersistentRetryTimer;
}
