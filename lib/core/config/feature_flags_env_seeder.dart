import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Seeds performance-related feature flags from `.env` when not yet persisted.
///
/// User choices in SharedPreferences always win; env only fills unset keys so
/// deployments can opt in (e.g. socket backpressure) without flipping code defaults.
///
/// Persisted prefs live in the global `settings.json` under the app data folder;
/// values already stored there override `.env` seeding and survive reinstalls of
/// the same profile. VS Code `.vscode/settings.json` does not affect runtime flags.
class FeatureFlagsEnvSeeder {
  FeatureFlagsEnvSeeder._();

  /// Uppercase env aliases mapped to persisted `feature_*` preference keys.
  ///
  /// `ENABLE_SOCKET_BACKPRESSURE` is opt-in (default false) for backward
  /// compatibility; set to `true` in `.env` to seed backpressure on first boot.
  static const Map<String, String> _envBoolAliases = <String, String>{
    'ENABLE_SOCKET_BACKPRESSURE': 'feature_enable_socket_backpressure',
    'ENABLE_SOCKET_IDEMPOTENCY': 'feature_enable_socket_idempotency',
    'ENABLE_SOCKET_REVOKED_TOKEN_IN_SESSION': 'feature_enable_socket_revoked_token_in_session',
  };

  static Future<void> applyUnsetOverrides(IAppSettingsStore prefs) async {
    for (final entry in _envBoolEntries()) {
      final key = entry.key;
      if (prefs.containsKey(key)) {
        continue;
      }

      final parsed = _parseBool(entry.value);
      if (parsed != null) {
        await prefs.setBool(key, parsed);
      }
    }
  }

  static Iterable<MapEntry<String, String>> _envBoolEntries() sync* {
    final snapshot = AppEnvironment.snapshot();
    for (final entry in snapshot.entries) {
      final key = entry.key.trim();
      if (key.startsWith('feature_')) {
        yield MapEntry(key, entry.value);
      }
    }
    for (final alias in _envBoolAliases.entries) {
      final value = snapshot[alias.key];
      if (value != null) {
        yield MapEntry(alias.value, value);
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
