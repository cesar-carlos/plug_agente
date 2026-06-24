import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags_performance_defaults_migrator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('FeatureFlagsPerformanceDefaultsMigrator', () {
    test('flips legacy false socket perf defaults once', () async {
      final prefs = InMemoryAppSettingsStore(<String, Object>{
        'feature_enable_socket_delivery_guarantees': false,
        'feature_enable_socket_streaming_chunks': false,
      });

      await FeatureFlagsPerformanceDefaultsMigrator.apply(prefs);

      expect(prefs.getBool('feature_enable_socket_delivery_guarantees'), isTrue);
      expect(prefs.getBool('feature_enable_socket_streaming_chunks'), isTrue);
      expect(prefs.getBool('feature_flags_perf_defaults_migrated_v1'), isTrue);

      await prefs.setBool('feature_enable_socket_delivery_guarantees', false);
      await FeatureFlagsPerformanceDefaultsMigrator.apply(prefs);
      expect(prefs.getBool('feature_enable_socket_delivery_guarantees'), isFalse);
    });
  });
}
