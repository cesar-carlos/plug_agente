import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/feature_flags_env_seeder.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('FeatureFlagsEnvSeeder', () {
    tearDown(() async {
      await dotenv.load(isOptional: true);
    });

    test('seeds unset feature_* booleans from environment snapshot', () async {
      dotenv.loadFromString(
        envString: 'feature_enable_socket_backpressure=true\nfeature_enable_socket_streaming_chunks=true',
      );
      final store = InMemoryAppSettingsStore();

      await FeatureFlagsEnvSeeder.applyUnsetOverrides(store);

      final flags = FeatureFlags(store);
      expect(flags.enableSocketBackpressure, isTrue);
      expect(flags.enableSocketStreamingChunks, isTrue);
      expect(store.getBool('feature_enable_socket_backpressure'), isTrue);
    });

    test('does not override persisted feature flags', () async {
      dotenv.loadFromString(envString: 'feature_enable_socket_backpressure=true');
      final store = InMemoryAppSettingsStore({
        'feature_enable_socket_backpressure': false,
      });

      await FeatureFlagsEnvSeeder.applyUnsetOverrides(store);

      expect(FeatureFlags(store).enableSocketBackpressure, isFalse);
    });

    test('seeds ENABLE_SOCKET_BACKPRESSURE alias when unset', () async {
      dotenv.loadFromString(envString: 'ENABLE_SOCKET_BACKPRESSURE=true');
      final store = InMemoryAppSettingsStore();

      await FeatureFlagsEnvSeeder.applyUnsetOverrides(store);

      expect(FeatureFlags(store).enableSocketBackpressure, isTrue);
    });

    test('ignores non-boolean feature flag values', () async {
      dotenv.loadFromString(envString: 'feature_enable_socket_backpressure=maybe');
      final store = InMemoryAppSettingsStore();

      await FeatureFlagsEnvSeeder.applyUnsetOverrides(store);

      expect(store.containsKey('feature_enable_socket_backpressure'), isFalse);
      expect(FeatureFlags(store).enableSocketBackpressure, isFalse);
    });
  });
}
