import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/domain/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/infrastructure/repositories/update_circuit_breaker_persistence.dart';

class UpdatePreferencesRepository implements IUpdatePreferencesRepository {
  UpdatePreferencesRepository({required IAppSettingsStore settingsStore})
    : _settingsStore = settingsStore,
      _manualTimeoutCircuitPersistence = UpdatePreferencesCircuitBreakerPersistence(
        settingsStore: settingsStore,
        countKey: AutoUpdateSettingsKeys.timeoutConsecutiveCount,
        cooldownKey: AutoUpdateSettingsKeys.timeoutCooldownUntilMs,
      ),
      _automaticFailureCircuitPersistence = UpdatePreferencesCircuitBreakerPersistence(
        settingsStore: settingsStore,
        countKey: AutoUpdateSettingsKeys.automaticFailureCount,
        cooldownKey: AutoUpdateSettingsKeys.automaticCooldownUntilMs,
      );

  final IAppSettingsStore _settingsStore;
  final ICircuitBreakerPersistence _manualTimeoutCircuitPersistence;
  final ICircuitBreakerPersistence _automaticFailureCircuitPersistence;

  @override
  bool get updateNotificationsEnabled => _settingsStore.getBool(AppSettingsKeys.updateNotificationsEnabled) ?? true;

  @override
  bool get automaticSilentUpdatesEnabled =>
      _settingsStore.getBool(AppSettingsKeys.automaticSilentUpdatesEnabled) ?? true;

  @override
  bool get automaticSilentUpdatesAutoApplyEnabled =>
      _settingsStore.getBool(AppSettingsKeys.automaticSilentUpdatesAutoApplyEnabled) ?? true;

  @override
  Future<void> setUpdateNotificationsEnabled(bool enabled) =>
      _settingsStore.setBool(AppSettingsKeys.updateNotificationsEnabled, enabled);

  @override
  Future<void> setAutomaticSilentUpdatesEnabled(bool enabled) =>
      _settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, enabled);

  @override
  Future<void> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled) =>
      _settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesAutoApplyEnabled, enabled);

  @override
  String? readLastManualDiagnosticsJson() => _settingsStore.getString(AutoUpdateSettingsKeys.lastManualDiagnostics);

  @override
  String? readLastBackgroundDiagnosticsJson() =>
      _settingsStore.getString(AutoUpdateSettingsKeys.lastBackgroundDiagnostics);

  @override
  String? readLastAutomaticDiagnosticsJson() =>
      _settingsStore.getString(AutoUpdateSettingsKeys.lastAutomaticDiagnostics);

  @override
  Future<void> writeLastManualDiagnosticsJson(String json) =>
      _settingsStore.setString(AutoUpdateSettingsKeys.lastManualDiagnostics, json);

  @override
  Future<void> writeLastBackgroundDiagnosticsJson(String json) =>
      _settingsStore.setString(AutoUpdateSettingsKeys.lastBackgroundDiagnostics, json);

  @override
  Future<void> writeLastAutomaticDiagnosticsJson(String json) =>
      _settingsStore.setString(AutoUpdateSettingsKeys.lastAutomaticDiagnostics, json);

  @override
  Future<void> clearLastAutomaticDiagnosticsJson() =>
      _settingsStore.remove(AutoUpdateSettingsKeys.lastAutomaticDiagnostics);

  @override
  String? readPendingSilentUpdateJson() {
    final store = _settingsStore;
    final integrity = store is IAppSettingsReadIntegrity ? store as IAppSettingsReadIntegrity : null;
    if (integrity?.readIntegrityError != null) {
      throw domain.ValidationFailure.withContext(
        message: 'O armazenamento da atualização exige recuperação.',
        cause: integrity!.readIntegrityError,
        context: const {'reason': 'settings_corrupted', 'outcome_unknown': true},
      );
    }
    final value = store.getValue(AutoUpdateSettingsKeys.pendingSilentUpdate);
    if (value != null && value is! String) {
      throw domain.ValidationFailure.withContext(
        message: 'O registro da atualização está inválido. Verifique a recuperação.',
        context: const {'reason': 'pending_corrupted', 'outcome_unknown': true},
      );
    }
    return value as String?;
  }

  @override
  Future<void> writePendingSilentUpdateJson(String json) =>
      _settingsStore.setString(AutoUpdateSettingsKeys.pendingSilentUpdate, json);

  @override
  Future<void> clearPendingSilentUpdateJson() => _settingsStore.remove(AutoUpdateSettingsKeys.pendingSilentUpdate);

  @override
  int? readRolloutBucket() => _settingsStore.getInt(AutoUpdateSettingsKeys.rolloutBucket);

  @override
  Future<void> writeRolloutBucket(int bucket) => _settingsStore.setInt(AutoUpdateSettingsKeys.rolloutBucket, bucket);

  @override
  Future<void> flushPendingPersistence() => _settingsStore.flushPendingPersistence();

  @override
  Object? get lastPersistError => _settingsStore.lastPersistError;

  @override
  ICircuitBreakerPersistence manualTimeoutCircuitPersistence() => _manualTimeoutCircuitPersistence;

  @override
  ICircuitBreakerPersistence automaticFailureCircuitPersistence() => _automaticFailureCircuitPersistence;
}
