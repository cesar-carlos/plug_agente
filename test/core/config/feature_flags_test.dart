import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('FeatureFlags', () {
    test('keeps binary payload enabled even with legacy disabled preference', () async {
      final store = InMemoryAppSettingsStore({
        'feature_enable_binary_payload': false,
      });
      final flags = FeatureFlags(store);

      expect(flags.enableBinaryPayload, isTrue);

      await flags.setEnableBinaryPayload(false);

      expect(flags.enableBinaryPayload, isTrue);
      expect(store.getBool('feature_enable_binary_payload'), isTrue);
    });
  });
}
