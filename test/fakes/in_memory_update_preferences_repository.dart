import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';

/// Lightweight update preferences repository for unit tests when neither
/// persisted preferences nor a settings store should be wired.
///
/// In-memory stand-in for update preference reads/writes in orchestrator and
/// coordinator unit tests.
class InMemoryUpdatePreferencesRepository implements IUpdatePreferencesRepository {
  InMemoryUpdatePreferencesRepository({
    bool updateNotificationsEnabled = true,
    bool automaticSilentUpdatesEnabled = true,
    bool freezeUpdateNotifications = false,
  }) : _updateNotificationsEnabled = updateNotificationsEnabled,
       _automaticSilentUpdatesEnabled = automaticSilentUpdatesEnabled,
       _freezeUpdateNotifications = freezeUpdateNotifications;

  bool _updateNotificationsEnabled;
  bool _automaticSilentUpdatesEnabled;
  final bool _freezeUpdateNotifications;

  String? _lastManualDiagnosticsJson;
  String? _lastBackgroundDiagnosticsJson;
  String? _lastAutomaticDiagnosticsJson;
  String? _pendingSilentUpdateJson;
  int? _rolloutBucket;

  final InMemoryCircuitBreakerPersistence _manualTimeoutCircuit = InMemoryCircuitBreakerPersistence();
  final InMemoryCircuitBreakerPersistence _automaticFailureCircuit = InMemoryCircuitBreakerPersistence();

  @override
  bool get updateNotificationsEnabled => _updateNotificationsEnabled;

  @override
  bool get automaticSilentUpdatesEnabled => _automaticSilentUpdatesEnabled;

  @override
  Future<void> setUpdateNotificationsEnabled(bool enabled) async {
    if (_freezeUpdateNotifications) {
      return;
    }
    _updateNotificationsEnabled = enabled;
  }

  @override
  Future<void> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    _automaticSilentUpdatesEnabled = enabled;
  }

  @override
  String? readLastManualDiagnosticsJson() => _lastManualDiagnosticsJson;

  @override
  String? readLastBackgroundDiagnosticsJson() => _lastBackgroundDiagnosticsJson;

  @override
  String? readLastAutomaticDiagnosticsJson() => _lastAutomaticDiagnosticsJson;

  @override
  Future<void> writeLastManualDiagnosticsJson(String json) async {
    _lastManualDiagnosticsJson = json;
  }

  @override
  Future<void> writeLastBackgroundDiagnosticsJson(String json) async {
    _lastBackgroundDiagnosticsJson = json;
  }

  @override
  Future<void> writeLastAutomaticDiagnosticsJson(String json) async {
    _lastAutomaticDiagnosticsJson = json;
  }

  @override
  Future<void> clearLastAutomaticDiagnosticsJson() async {
    _lastAutomaticDiagnosticsJson = null;
  }

  @override
  String? readPendingSilentUpdateJson() => _pendingSilentUpdateJson;

  @override
  Future<void> writePendingSilentUpdateJson(String json) async {
    _pendingSilentUpdateJson = json;
  }

  @override
  Future<void> clearPendingSilentUpdateJson() async {
    _pendingSilentUpdateJson = null;
  }

  @override
  int? readRolloutBucket() => _rolloutBucket;

  @override
  Future<void> writeRolloutBucket(int bucket) async {
    _rolloutBucket = bucket;
  }

  @override
  Future<void> flushPendingPersistence() async {}

  @override
  ICircuitBreakerPersistence manualTimeoutCircuitPersistence() => _manualTimeoutCircuit;

  @override
  ICircuitBreakerPersistence automaticFailureCircuitPersistence() => _automaticFailureCircuit;
}
