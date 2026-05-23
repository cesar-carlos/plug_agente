import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Preflight TTL for activating agent actions.
///
/// Persisted value in [IAppSettingsStore] overrides [AgentActionPolicyDefaults]
/// (which reads `AGENT_ACTION_PREFLIGHT_VALIDITY_DAYS`) for this installation.
class AgentActionPreflightSettings {
  AgentActionPreflightSettings(this._store);

  static const String preflightValidityDaysKey = 'agent_action_preflight_validity_days';

  static const int minValidityDays = 1;
  static const int maxValidityDays = 365;

  final IAppSettingsStore _store;

  Duration get validityDuration {
    final stored = _store.getInt(preflightValidityDaysKey);
    if (stored != null) {
      return Duration(days: _clampDays(stored));
    }
    return AgentActionPolicyDefaults.preflightValidityDuration;
  }

  int get validityDays => validityDuration.inDays;

  bool get hasPersistedOverride => _store.getInt(preflightValidityDaysKey) != null;

  Future<void> save({required int validityDays}) async {
    final normalized = _clampDays(validityDays);
    await _store.setInt(preflightValidityDaysKey, normalized);
    await _store.flushPendingPersistence();
  }

  Future<void> clearPersistedOverride() async {
    await _store.remove(preflightValidityDaysKey);
    await _store.flushPendingPersistence();
  }

  static int _clampDays(int value) {
    if (value < minValidityDays) {
      return minValidityDays;
    }
    if (value > maxValidityDays) {
      return maxValidityDays;
    }
    return value;
  }
}
