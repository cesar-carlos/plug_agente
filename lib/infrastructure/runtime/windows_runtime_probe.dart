import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:win32/win32.dart';

/// Interface para detecção de versão do Windows.
abstract class IWindowsRuntimeProbe {
  Future<Result<WindowsVersionInfo>> detect();
}

/// Implementação de detecção de versão do Windows usando Win32 API.
class WindowsRuntimeProbe implements IWindowsRuntimeProbe {
  @override
  Future<Result<WindowsVersionInfo>> detect() async {
    try {
      final versionInfo = calloc<OSVERSIONINFOEX>();
      versionInfo.ref.dwOSVersionInfoSize = sizeOf<OSVERSIONINFOEX>();

      final rtlGetVersion = DynamicLibrary.open('ntdll.dll')
          .lookupFunction<
            Int32 Function(Pointer<OSVERSIONINFOEX>),
            int Function(Pointer<OSVERSIONINFOEX>)
          >('RtlGetVersion');

      final result = rtlGetVersion(versionInfo);

      if (result != 0) {
        calloc.free(versionInfo);
        return _fallbackDetection();
      }

      final info = WindowsVersionInfo(
        majorVersion: versionInfo.ref.dwMajorVersion,
        minorVersion: versionInfo.ref.dwMinorVersion,
        buildNumber: versionInfo.ref.dwBuildNumber,
        isServer: versionInfo.ref.wProductType != VER_NT_WORKSTATION,
        productName: _getProductName(versionInfo.ref),
      );

      calloc.free(versionInfo);

      developer.log(
        'Windows version detected: $info',
        name: 'runtime_probe',
        level: 800,
      );

      return Success(info);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to detect Windows version via RtlGetVersion',
        name: 'runtime_probe',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return _fallbackDetection();
    }
  }

  String? _getProductName(OSVERSIONINFOEX versionInfo) {
    final major = versionInfo.dwMajorVersion;
    final minor = versionInfo.dwMinorVersion;
    final isServer = versionInfo.wProductType != VER_NT_WORKSTATION;

    if (major == 10 && minor == 0) {
      return isServer ? 'Windows Server 2016+' : 'Windows 10/11';
    } else if (major == 6 && minor == 3) {
      return isServer ? 'Windows Server 2012 R2' : 'Windows 8.1';
    } else if (major == 6 && minor == 2) {
      return isServer ? 'Windows Server 2012' : 'Windows 8';
    } else if (major == 6 && minor == 1) {
      return isServer ? 'Windows Server 2008 R2' : 'Windows 7';
    }
    return null;
  }

  Result<WindowsVersionInfo> _fallbackDetection() {
    try {
      final osVersion = Platform.operatingSystemVersion;
      developer.log(
        'Using fallback detection from Platform.operatingSystemVersion: $osVersion',
        name: 'runtime_probe',
        level: 800,
      );

      final regex = RegExp(r'Version (\d+)\.(\d+)\.(\d+)');
      final match = regex.firstMatch(osVersion);

      if (match != null) {
        final major = int.parse(match.group(1)!);
        final minor = int.parse(match.group(2)!);
        final build = int.parse(match.group(3)!);

        final info = WindowsVersionInfo(
          majorVersion: major,
          minorVersion: minor,
          buildNumber: build,
          isServer: false,
          productName: 'Windows (fallback detection)',
        );

        return Success(info);
      }

      return Failure(
        domain.ConfigurationFailure(
          'Could not parse Windows version from: $osVersion',
        ),
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Fallback detection failed',
        name: 'runtime_probe',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      return Failure(
        domain.ConfigurationFailure('Failed to detect Windows version: $e'),
      );
    }
  }
}
