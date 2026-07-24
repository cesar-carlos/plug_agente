import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';

void main() {
  group('StartupApprovedBinary', () {
    test('classifies enabled status dwords 0x02 and 0x06', () {
      check(
        StartupApprovedBinary.classify(
          Uint8List.fromList(const <int>[0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        ),
      ).equals(StartupApprovedStatus.enabled);
      check(
        StartupApprovedBinary.classify(
          Uint8List.fromList(const <int>[0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        ),
      ).equals(StartupApprovedStatus.enabled);
    });

    test('classifies disabled status dword 0x03', () {
      check(
        StartupApprovedBinary.classify(
          Uint8List.fromList(const <int>[0x03, 0x00, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
        ),
      ).equals(StartupApprovedStatus.disabled);
    });

    test('classifies unknown and truncated payloads as unknown', () {
      check(
        StartupApprovedBinary.classify(Uint8List.fromList(const <int>[0x09, 0x00, 0x00, 0x00])),
      ).equals(StartupApprovedStatus.unknown);
      check(
        StartupApprovedBinary.classify(Uint8List.fromList(const <int>[0x02, 0x00])),
      ).equals(StartupApprovedStatus.unknown);
    });

    test('enabledPayload classifies as enabled', () {
      check(
        StartupApprovedBinary.classify(StartupApprovedBinary.enabledPayload),
      ).equals(StartupApprovedStatus.enabled);
    });
  });

  group('StartupApprovedReadResult', () {
    test('treats notPresent and enabled as effectively enabled', () {
      check(const StartupApprovedReadResult.notPresent().isEffectivelyEnabled).isTrue();
      check(const StartupApprovedReadResult.enabled().isEffectivelyEnabled).isTrue();
      check(const StartupApprovedReadResult.disabled().isEffectivelyEnabled).isFalse();
    });

    test('treats disabled and unknown as effectively disabled', () {
      check(const StartupApprovedReadResult.disabled().isEffectivelyDisabled).isTrue();
      check(const StartupApprovedReadResult.unknown().isEffectivelyDisabled).isTrue();
      check(const StartupApprovedReadResult.accessDenied(5).isEffectivelyDisabled).isFalse();
    });
  });
}
