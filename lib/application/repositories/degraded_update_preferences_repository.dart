import 'package:plug_agente/application/repositories/file_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';

/// Non-persisted update preferences for degraded runtimes without a settings store.
///
/// Used when no persisted [IUpdatePreferencesRepository] is wired. Preference
/// toggles from the UI still fail at the orchestrator boundary; this repository
/// only satisfies internal auto-update services.
class DegradedUpdatePreferencesRepository implements IUpdatePreferencesRepository {
  DegradedUpdatePreferencesRepository({
    String? circuitBreakerBasePath,
  }) : _manualTimeoutCircuit = FileCircuitBreakerPersistence(
         fileName: 'manual_timeout_cb.json',
         basePath: circuitBreakerBasePath,
       ),
       _automaticFailureCircuit = FileCircuitBreakerPersistence(
         fileName: 'automatic_failure_cb.json',
         basePath: circuitBreakerBasePath,
       );

  bool _updateNotificationsEnabled = true;
  bool _automaticSilentUpdatesEnabled = true;
  bool _automaticSilentUpdatesAutoApplyEnabled = true;

  final ICircuitBreakerPersistence _manualTimeoutCircuit;
  final ICircuitBreakerPersistence _automaticFailureCircuit;

  @override
  bool get updateNotificationsEnabled => _updateNotificationsEnabled;

  @override
  bool get automaticSilentUpdatesEnabled => _automaticSilentUpdatesEnabled;

  @override
  bool get automaticSilentUpdatesAutoApplyEnabled => _automaticSilentUpdatesAutoApplyEnabled;

  @override
  Future<void> setUpdateNotificationsEnabled(bool enabled) async {
    _updateNotificationsEnabled = enabled;
  }

  @override
  Future<void> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    _automaticSilentUpdatesEnabled = enabled;
  }

  @override
  Future<void> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled) async {
    _automaticSilentUpdatesAutoApplyEnabled = enabled;
  }

  @override
  String? readLastManualDiagnosticsJson() => null;

  @override
  String? readLastBackgroundDiagnosticsJson() => null;

  @override
  String? readLastAutomaticDiagnosticsJson() => null;

  @override
  Future<void> writeLastManualDiagnosticsJson(String json) async {}

  @override
  Future<void> writeLastBackgroundDiagnosticsJson(String json) async {}

  @override
  Future<void> writeLastAutomaticDiagnosticsJson(String json) async {}

  @override
  Future<void> clearLastAutomaticDiagnosticsJson() async {}

  @override
  String? readPendingSilentUpdateJson() => null;

  @override
  Future<void> writePendingSilentUpdateJson(String json) async {}

  @override
  Future<void> clearPendingSilentUpdateJson() async {}

  @override
  int? readRolloutBucket() => null;

  @override
  Future<void> writeRolloutBucket(int bucket) async {}

  @override
  Future<void> flushPendingPersistence() async {}

  @override
  ICircuitBreakerPersistence manualTimeoutCircuitPersistence() => _manualTimeoutCircuit;

  @override
  ICircuitBreakerPersistence automaticFailureCircuitPersistence() => _automaticFailureCircuit;
}
