import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/config/payload_signing_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('PayloadSigningDiagnostics', () {
    test('should report blocking issue when signing is enabled without key', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnablePayloadSigning(true);

      final diagnostics = PayloadSigningDiagnostics.evaluate(
        featureFlags: flags,
        config: PayloadSigningConfig.empty(),
      );

      expect(diagnostics.status, PayloadSigningHealthStatus.error);
      expect(diagnostics.hasBlockingIssue, isTrue);
      expect(
        diagnostics.issues.map((issue) => issue.code),
        contains('payload_signing_enabled_without_key'),
      );
    });

    test('should mark multi-key signer as rotation ready', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final diagnostics = PayloadSigningDiagnostics.evaluate(
        featureFlags: flags,
        config: PayloadSigningConfig(
          activeKeyId: 'v2',
          keys: const <String, String>{
            'v1': 'old-secret',
            'v2': 'new-secret',
          },
        ),
      );

      expect(diagnostics.status, PayloadSigningHealthStatus.ok);
      expect(diagnostics.rotationReady, isTrue);
      expect(diagnostics.toJson()['key_count'], equals(2));
    });

    test('should warn when only one key is configured', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final diagnostics = PayloadSigningDiagnostics.evaluate(
        featureFlags: flags,
        config: PayloadSigningConfig(
          activeKeyId: 'v1',
          keys: const <String, String>{'v1': 'secret'},
        ),
      );

      expect(diagnostics.status, PayloadSigningHealthStatus.warning);
      expect(
        diagnostics.issues.map((issue) => issue.code),
        contains('payload_signing_rotation_single_key'),
      );
    });
  });
}
