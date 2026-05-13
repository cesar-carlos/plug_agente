import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
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

    test('keeps incoming payload signatures optional by default', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);

      expect(flags.enablePayloadSigning, isFalse);
      expect(flags.requireIncomingPayloadSignatures, isFalse);

      await flags.setEnablePayloadSigning(true);

      expect(flags.enablePayloadSigning, isTrue);
      expect(flags.requireIncomingPayloadSignatures, isFalse);
    });

    test('uses balanced compression defaults for transport performance', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      expect(flags.outboundCompressionMode, OutboundCompressionMode.auto);
      expect(flags.enableCompression, isTrue);
      expect(flags.compressionThreshold, 4096);
    });

    test('keeps experimental adaptive ODBC pooling disabled by default', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isFalse);

      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(true);

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isTrue);
      expect(store.getBool('feature_enable_odbc_experimental_driver_adaptive_pooling'), isTrue);
    });

    test('resets experimental adaptive ODBC pooling to disabled default', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(true);

      await flags.resetToDefaults();

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isFalse);
    });

    test('enables DB streaming path by default when socket chunking is enabled separately', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      expect(flags.enableSocketStreamingFromDb, isTrue);
      expect(flags.enableSocketStreamingChunks, isFalse);
    });
  });
}
