import 'package:plug_agente/core/settings/app_settings_store.dart';

/// One-time migration for socket performance defaults shipped in 2026-05.
///
/// Installs that persisted the pre-ship `false` defaults in `settings.json`
/// keep those values forever unless migrated. This flips them to the current
/// code defaults once per profile.
abstract final class FeatureFlagsPerformanceDefaultsMigrator {
  static const _migrationKey = 'feature_flags_perf_defaults_migrated_v1';
  static const _keyDeliveryGuarantees = 'feature_enable_socket_delivery_guarantees';
  static const _keyStreamingChunks = 'feature_enable_socket_streaming_chunks';

  static Future<void> apply(IAppSettingsStore prefs) async {
    if (prefs.getBool(_migrationKey) ?? false) {
      return;
    }

    if (prefs.getBool(_keyDeliveryGuarantees) == false) {
      await prefs.setBool(_keyDeliveryGuarantees, true);
    }
    if (prefs.getBool(_keyStreamingChunks) == false) {
      await prefs.setBool(_keyStreamingChunks, true);
    }

    await prefs.setBool(_migrationKey, true);
  }
}
