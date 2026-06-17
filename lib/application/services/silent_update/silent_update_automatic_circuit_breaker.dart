import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';

/// Creates the persistent circuit breaker wired into the silent update flow.
PersistentCircuitBreaker createSilentUpdateAutomaticFailureBreaker({
  required IUpdatePreferencesRepository preferences,
  int threshold = AutoUpdateDefaults.automaticFailureCooldownThreshold,
  Duration cooldown = AutoUpdateDefaults.automaticFailureCooldown,
  DateTime Function()? clock,
}) {
  return PersistentCircuitBreaker(
    persistence: preferences.automaticFailureCircuitPersistence(),
    threshold: threshold,
    cooldown: cooldown,
    logName: 'silent_update_coordinator',
    clock: clock,
  );
}
