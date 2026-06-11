import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Seeds performance-related feature flags from `.env` when not yet persisted.
///
/// User choices in SharedPreferences always win; env only fills unset keys so
/// deployments can opt in (e.g. socket backpressure) without flipping code defaults.
class FeatureFlagsEnvSeeder {
  FeatureFlagsEnvSeeder._();

  static Future<void> applyUnsetOverrides(IAppSettingsStore prefs) async {
    for (final entry in AppEnvironment.snapshot().entries) {
      final key = entry.key.trim();
      if (!key.startsWith('feature_')) {
        continue;
      }
      if (prefs.containsKey(key)) {
        continue;
      }

      final parsed = _parseBool(entry.value);
      if (parsed != null) {
        await prefs.setBool(key, parsed);
      }
    }
  }

  static bool? _parseBool(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'true' || '1' || 'yes' || 'on' => true,
      'false' || '0' || 'no' || 'off' => false,
      _ => null,
    };
  }
}
