import 'package:plug_agente/application/services/auto_update_defaults.dart';

/// Groups the silent-update coordinator's policy knobs so the
/// constructor stays focused on dependencies (gateways, stores,
/// readers) and the long list of timing/threshold values lives in a
/// cohesive bundle.
class SilentUpdateCoordinatorOptions {
  const SilentUpdateCoordinatorOptions({
    this.automaticFailureCooldownThreshold = AutoUpdateDefaults.automaticFailureCooldownThreshold,
    this.automaticFailureCooldown = AutoUpdateDefaults.automaticFailureCooldown,
    this.helperWaitDuration = AutoUpdateDefaults.helperWaitDuration,
  });

  /// Consecutive automatic failures before the silent breaker enters
  /// its cooldown window.
  final int automaticFailureCooldownThreshold;

  /// Cooldown duration once the silent breaker trips.
  final Duration automaticFailureCooldown;

  /// Maximum window during which the reconciler keeps an in-flight
  /// helper marked as "still running" before failing the pending
  /// record.
  final Duration helperWaitDuration;

  SilentUpdateCoordinatorOptions copyWith({
    int? automaticFailureCooldownThreshold,
    Duration? automaticFailureCooldown,
    Duration? helperWaitDuration,
  }) {
    return SilentUpdateCoordinatorOptions(
      automaticFailureCooldownThreshold:
          automaticFailureCooldownThreshold ?? this.automaticFailureCooldownThreshold,
      automaticFailureCooldown: automaticFailureCooldown ?? this.automaticFailureCooldown,
      helperWaitDuration: helperWaitDuration ?? this.helperWaitDuration,
    );
  }
}
