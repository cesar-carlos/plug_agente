import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';

/// Single owner for auto-update preference flags, diagnostics JSON blobs,
/// rollout bucket, pending silent-update persistence keys, and update-scoped
/// circuit breaker state.
abstract interface class IUpdatePreferencesRepository {
  bool get updateNotificationsEnabled;
  bool get automaticSilentUpdatesEnabled;
  bool get automaticSilentUpdatesAutoApplyEnabled;

  Future<void> setUpdateNotificationsEnabled(bool enabled);
  Future<void> setAutomaticSilentUpdatesEnabled(bool enabled);
  Future<void> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled);

  String? readLastManualDiagnosticsJson();
  String? readLastBackgroundDiagnosticsJson();
  String? readLastAutomaticDiagnosticsJson();

  Future<void> writeLastManualDiagnosticsJson(String json);
  Future<void> writeLastBackgroundDiagnosticsJson(String json);
  Future<void> writeLastAutomaticDiagnosticsJson(String json);
  Future<void> clearLastAutomaticDiagnosticsJson();

  String? readPendingSilentUpdateJson();
  Future<void> writePendingSilentUpdateJson(String json);
  Future<void> clearPendingSilentUpdateJson();

  int? readRolloutBucket();
  Future<void> writeRolloutBucket(int bucket);

  /// Persists any buffered settings writes. No-op when the backing store
  /// does not support deferred persistence.
  Future<void> flushPendingPersistence();

  /// Manual WinSparkle check timeout circuit (`timeout_*` keys).
  ICircuitBreakerPersistence manualTimeoutCircuitPersistence();

  /// Automatic silent-update failure circuit (`automatic_failure_*` keys).
  ICircuitBreakerPersistence automaticFailureCircuitPersistence();
}
