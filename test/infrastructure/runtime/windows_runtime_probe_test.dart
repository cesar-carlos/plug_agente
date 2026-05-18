import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:win32/win32.dart';

void main() {
  group('WindowsRuntimeProbe', () {
    test('uses RtlGetVersion diagnostics when native detection succeeds', () async {
      final probe = WindowsRuntimeProbe(
        rtlGetVersionInvoker: (Pointer<OSVERSIONINFOEX> versionInfo) {
          versionInfo.ref
            ..dwMajorVersion = 10
            ..dwMinorVersion = 0
            ..dwBuildNumber = 26200
            ..wProductType = VER_NT_WORKSTATION;
          return 0;
        },
      );

      final result = await probe.detect();

      expect(result.isSuccess(), isTrue);
      final versionInfo = result.getOrThrow();
      expect(versionInfo.versionString, '10.0.26200');
      expect(versionInfo.isServer, isFalse);
      expect(versionInfo.productName, 'Windows 10/11');
      expect(probe.lastDiagnostics?.source, RuntimeDetectionSource.rtlGetVersion);
      expect(probe.lastDiagnostics?.versionInfo?.versionString, '10.0.26200');
    });

    test('falls back to Platform.operatingSystemVersion and records raw OS text', () async {
      final probe = WindowsRuntimeProbe(
        rtlGetVersionInvoker: (_) => 1,
        operatingSystemVersionProvider: () => 'Microsoft Windows Server Version 10.0.17763',
      );

      final result = await probe.detect();

      expect(result.isSuccess(), isTrue);
      final versionInfo = result.getOrThrow();
      expect(versionInfo.versionString, '10.0.17763');
      expect(versionInfo.isServer, isTrue);
      expect(probe.lastDiagnostics?.source, RuntimeDetectionSource.platformOperatingSystemVersion);
      expect(
        probe.lastDiagnostics?.rawOperatingSystemVersion,
        'Microsoft Windows Server Version 10.0.17763',
      );
    });

    test('records detection failure when fallback text cannot be parsed', () async {
      final probe = WindowsRuntimeProbe(
        rtlGetVersionInvoker: (_) => 1,
        operatingSystemVersionProvider: () => 'unexpected os string',
      );

      final result = await probe.detect();

      expect(result.isError(), isTrue);
      expect(probe.lastDiagnostics?.source, RuntimeDetectionSource.detectionFailed);
      expect(
        probe.lastDiagnostics?.failureMessage,
        contains('Could not parse Windows version from: unexpected os string'),
      );
    });
  });
}
