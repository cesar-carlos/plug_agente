import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('AgentActionPreflightSettings', () {
    test('should use policy defaults when store has no override', () {
      final settings = AgentActionPreflightSettings(InMemoryAppSettingsStore());

      expect(settings.hasPersistedOverride, isFalse);
      expect(settings.validityDuration, AgentActionPolicyDefaults.preflightValidityDuration);
    });

    test('should persist and read validity days', () async {
      final store = InMemoryAppSettingsStore();
      final settings = AgentActionPreflightSettings(store);

      await settings.save(validityDays: 14);

      expect(settings.hasPersistedOverride, isTrue);
      expect(settings.validityDays, 14);
      expect(settings.validityDuration, const Duration(days: 14));
    });

    test('should clamp validity days to 1–365', () async {
      final settings = AgentActionPreflightSettings(InMemoryAppSettingsStore());

      await settings.save(validityDays: 0);
      expect(settings.validityDays, AgentActionPreflightSettings.minValidityDays);

      await settings.save(validityDays: 9999);
      expect(settings.validityDays, AgentActionPreflightSettings.maxValidityDays);
    });

    test('should clear persisted override and fall back to policy defaults', () async {
      final store = InMemoryAppSettingsStore();
      final settings = AgentActionPreflightSettings(store);

      await settings.save(validityDays: 42);
      expect(settings.hasPersistedOverride, isTrue);

      await settings.clearPersistedOverride();

      expect(settings.hasPersistedOverride, isFalse);
      expect(settings.validityDuration, AgentActionPolicyDefaults.preflightValidityDuration);
    });
  });
}
