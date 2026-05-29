import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';

void main() {
  group('UpdateCheckDiagnostics', () {
    test('round trips appcast os and validation error code', () {
      final diagnostics = UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 5, 22, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml?cb=1',
        appcastProbeVersion: '99.0.0+1',
        appcastProbeOs: 'windows',
        validationErrorCode: 'unsupported_os',
      );

      final restored = UpdateCheckDiagnostics.fromJson(
        Map<String, dynamic>.from(diagnostics.toJson()),
      );

      expect(restored, isNotNull);
      expect(restored!.appcastProbeOs, 'windows');
      expect(restored.validationErrorCode, 'unsupported_os');
    });
  });
}
