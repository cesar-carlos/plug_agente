import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

/// Applies hard-relogin outcomes to tracked session state and display status.
final class HubHardReloginExecutor {
  HubHardReloginExecutor({
    required HubHardReloginRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubHardReloginRuntimeDependencies _deps;

  Future<String?> execute(
    HubConnectionContext context, {
    required String logSummary,
    bool ignoreCooldown = false,
  }) async {
    _deps.setHubRecoveryUiHint(HubRecoveryUiHint.signingIn);
    final result = await _deps.resilienceCoordinator.executeHardRelogin(
      context,
      logSummary: logSummary,
      hardReloginCooldown: _deps.hardReloginCooldown,
      ignoreCooldown: ignoreCooldown,
    );

    switch (result.outcome) {
      case HardReloginOutcome.skippedCooldown:
        _deps.clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.authBridgeUnavailable:
        _deps.resilienceCoordinator.clearResilienceRecovery();
        _deps.onAuthBridgeUnavailable();
        _deps.cancelPersistentRetryTimer();
        _deps.clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.failed:
        _deps.onHardReloginFailed(result.failureMessage ?? 'Automatic relogin failed');
        _deps.cancelPersistentRetryTimer();
        _deps.resilienceCoordinator.clearResilienceRecovery();
        _deps.clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.success:
        return _deps.onHardReloginSuccess(result.token);
    }
  }
}

final class HubHardReloginRuntimeDependencies {
  HubHardReloginRuntimeDependencies({
    required this.resilienceCoordinator,
    required this.hardReloginCooldown,
    required this.setHubRecoveryUiHint,
    required this.clearHubRecoveryUiHint,
    required this.cancelPersistentRetryTimer,
    required this.onAuthBridgeUnavailable,
    required this.onHardReloginFailed,
    required this.onHardReloginSuccess,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final Duration hardReloginCooldown;
  final void Function(HubRecoveryUiHint hint) setHubRecoveryUiHint;
  final void Function() clearHubRecoveryUiHint;
  final void Function() cancelPersistentRetryTimer;
  final void Function() onAuthBridgeUnavailable;
  final void Function(String message) onHardReloginFailed;
  final String? Function(String? token) onHardReloginSuccess;
}
