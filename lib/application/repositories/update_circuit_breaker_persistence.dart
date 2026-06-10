import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart' show UpdatePreferencesRepository;
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Settings-backed circuit breaker state owned by [UpdatePreferencesRepository].
class UpdatePreferencesCircuitBreakerPersistence implements ICircuitBreakerPersistence {
  UpdatePreferencesCircuitBreakerPersistence({
    required IAppSettingsStore settingsStore,
    required this.countKey,
    required this.cooldownKey,
  }) : _settingsStore = settingsStore;

  final IAppSettingsStore _settingsStore;
  final String countKey;
  final String cooldownKey;

  @override
  int get failureCount => _settingsStore.getInt(countKey) ?? 0;

  @override
  DateTime? get cooldownUntil {
    final timestamp = _settingsStore.getInt(cooldownKey);
    if (timestamp == null || timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  @override
  Future<void> persistFailure({
    required int failureCount,
    DateTime? cooldownUntil,
  }) async {
    final values = <String, Object>{countKey: failureCount};
    if (cooldownUntil != null) {
      values[cooldownKey] = cooldownUntil.millisecondsSinceEpoch;
    }
    await _settingsStore.setValues(values);
  }

  @override
  Future<void> clear() async {
    if (_settingsStore.containsKey(countKey)) {
      await _settingsStore.remove(countKey);
    }
    if (_settingsStore.containsKey(cooldownKey)) {
      await _settingsStore.remove(cooldownKey);
    }
  }
}
