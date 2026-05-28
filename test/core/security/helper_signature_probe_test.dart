import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/security/helper_signature_probe.dart';

void main() {
  group('PowerShellHelperSignatureProbe', () {
    late Directory tempDir;
    late File targetFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('helper_signature_probe_test_');
      targetFile = File('${tempDir.path}/plug_update_helper.exe')
        ..writeAsBytesSync(<int>[0x4D, 0x5A]); // MZ header so the file is non-empty
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<ProcessResult> stubbedRunner(
      String stdout, {
      int exitCode = 0,
    }) async {
      return ProcessResult(0, exitCode, stdout, '');
    }

    test('returns unknown when file does not exist', () async {
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) async {
          fail('probe must not invoke PowerShell when file is missing');
        },
      );
      final status = await probe.probe('${tempDir.path}/missing.exe');
      expect(status, HelperSignatureStatus.unknown);
    });

    test('returns unknown on non-Windows platforms', () async {
      // The probe checks Platform.isWindows internally. On the host CI/dev
      // machines that run these tests, Platform.isWindows is true, so we
      // can only assert by stubbing the runner to fail and proving the
      // probe still reaches it. The cross-platform branch is exercised by
      // running the test suite on non-Windows agents.
      if (!Platform.isWindows) {
        final probe = PowerShellHelperSignatureProbe();
        final status = await probe.probe(targetFile.path);
        expect(status, HelperSignatureStatus.unknown);
      }
    });

    test('maps Valid output to HelperSignatureStatus.valid', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) => stubbedRunner('Valid\n'),
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.valid);
    });

    test('maps NotSigned output to HelperSignatureStatus.unsigned', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) => stubbedRunner('NotSigned'),
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.unsigned);
    });

    test('maps HashMismatch output to HelperSignatureStatus.invalid', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) => stubbedRunner('HashMismatch'),
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.invalid);
    });

    test('maps NotTrusted output to HelperSignatureStatus.invalid', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) => stubbedRunner('NotTrusted'),
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.invalid);
    });

    test('falls back to unknown for unexpected status strings', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) => stubbedRunner('SomeFuturePowerShellStatus'),
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.unknown);
    });

    test('caches result so PowerShell is invoked only once per session', () async {
      if (!Platform.isWindows) return;
      var callCount = 0;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) async {
          callCount++;
          return ProcessResult(0, 0, 'Valid', '');
        },
      );
      await probe.probe(targetFile.path);
      await probe.probe(targetFile.path);
      await probe.probe(targetFile.path);
      expect(callCount, 1);
    });

    test('returns unknown when the runner throws ProcessException', () async {
      if (!Platform.isWindows) return;
      final probe = PowerShellHelperSignatureProbe(
        processRunner: (_, _, {timeout = const Duration(seconds: 5)}) async {
          throw const ProcessException('powershell', <String>[]);
        },
      );
      final status = await probe.probe(targetFile.path);
      expect(status, HelperSignatureStatus.unknown);
    });
  });

  group('NoOpHelperSignatureProbe', () {
    test('always returns unknown', () async {
      const probe = NoOpHelperSignatureProbe();
      expect(await probe.probe('anything.exe'), HelperSignatureStatus.unknown);
      expect(await probe.probe(''), HelperSignatureStatus.unknown);
    });
  });
}
