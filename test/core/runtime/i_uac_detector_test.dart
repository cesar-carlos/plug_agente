import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';

void main() {
  group('NoopUacDetector', () {
    test('never reports that user consent is required', () {
      const detector = NoopUacDetector();

      expect(detector.requiresUserConsentForElevation(), isFalse);
    });

    test('is idempotent across repeated calls', () {
      const detector = NoopUacDetector();

      expect(detector.requiresUserConsentForElevation(), isFalse);
      expect(detector.requiresUserConsentForElevation(), isFalse);
      expect(detector.requiresUserConsentForElevation(), isFalse);
    });

    test('detect() returns the noop snapshot', () {
      const detector = NoopUacDetector();
      final state = detector.detect();

      expect(state, same(UacDetectionState.noop));
      expect(state.elevationType, UacElevationType.unknown);
      expect(state.requiresConsent, isFalse);
      expect(state.uacEnabled, isNull);
    });
  });

  group('UacDetectionState', () {
    test('failed snapshot defaults to requires consent and unknown elevation', () {
      const state = UacDetectionState.failed;

      expect(state.elevationType, UacElevationType.unknown);
      expect(state.uacEnabled, isNull);
      expect(state.requiresConsent, isTrue);
      expect(state.detectionError, isNotNull);
    });
  });
}
