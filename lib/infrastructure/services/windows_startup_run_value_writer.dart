import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:win32/win32.dart';

enum StartupRunValueWriteStatus {
  success,
  notFound,
  accessDenied,
  failed,
}

class StartupRunValueWriteResult {
  const StartupRunValueWriteResult._(this.status, this.nativeStatus);

  const StartupRunValueWriteResult.success() : this._(StartupRunValueWriteStatus.success, null);

  const StartupRunValueWriteResult.notFound() : this._(StartupRunValueWriteStatus.notFound, null);

  const StartupRunValueWriteResult.accessDenied(int nativeStatus)
    : this._(StartupRunValueWriteStatus.accessDenied, nativeStatus);

  const StartupRunValueWriteResult.failed(int nativeStatus) : this._(StartupRunValueWriteStatus.failed, nativeStatus);

  final StartupRunValueWriteStatus status;
  final int? nativeStatus;
}

abstract interface class IStartupRunValueRegistryWriter {
  StartupRunValueWriteResult setRunValue({
    required StartupRegistryScope scope,
    required String valueName,
    required String rawValueData,
  });

  StartupRunValueWriteResult deleteRunValue({
    required StartupRegistryScope scope,
    required String valueName,
  });
}

/// Writes/deletes Run values through Win32 registry APIs (locale-independent).
class Win32StartupRunValueRegistryWriter implements IStartupRunValueRegistryWriter {
  const Win32StartupRunValueRegistryWriter();

  static const String _runSubKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

  @override
  StartupRunValueWriteResult setRunValue({
    required StartupRegistryScope scope,
    required String valueName,
    required String rawValueData,
  }) {
    return _withRunKey(
      scope: scope,
      access: KEY_SET_VALUE,
      action: (hKey) {
        final valueNamePtr = valueName.toNativeUtf16();
        final encoded = Uint16List.fromList([...rawValueData.codeUnits, 0]);
        final dataPtr = calloc<Uint16>(encoded.length);
        try {
          dataPtr.asTypedList(encoded.length).setAll(0, encoded);
          final status = RegSetValueEx(
            hKey,
            valueNamePtr,
            0,
            REG_SZ,
            dataPtr.cast<Uint8>(),
            encoded.length * 2,
          );
          return _resultFromErrorStatus(status);
        } finally {
          calloc.free(dataPtr);
          calloc.free(valueNamePtr);
        }
      },
    );
  }

  @override
  StartupRunValueWriteResult deleteRunValue({
    required StartupRegistryScope scope,
    required String valueName,
  }) {
    return _withRunKey(
      scope: scope,
      access: KEY_SET_VALUE,
      action: (hKey) {
        final valueNamePtr = valueName.toNativeUtf16();
        try {
          final status = RegDeleteValue(hKey, valueNamePtr);
          if (status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND) {
            return const StartupRunValueWriteResult.success();
          }
          return _resultFromErrorStatus(status);
        } finally {
          calloc.free(valueNamePtr);
        }
      },
    );
  }

  StartupRunValueWriteResult _withRunKey({
    required StartupRegistryScope scope,
    required int access,
    required StartupRunValueWriteResult Function(int hKey) action,
  }) {
    final rootKey = scope == StartupRegistryScope.currentUser ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
    final wowFlag = switch (scope) {
      StartupRegistryScope.currentUser => 0,
      StartupRegistryScope.localMachine => KEY_WOW64_64KEY,
      StartupRegistryScope.localMachineWow6432 => KEY_WOW64_32KEY,
    };

    final subKeyPtr = _runSubKeyPath.toNativeUtf16();
    final hKeyOut = calloc<IntPtr>();
    try {
      final openStatus = RegOpenKeyEx(
        rootKey,
        subKeyPtr,
        0,
        access | wowFlag,
        hKeyOut,
      );
      if (openStatus != ERROR_SUCCESS) {
        return _resultFromErrorStatus(openStatus);
      }
      final hKey = hKeyOut.value;
      try {
        return action(hKey);
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(hKeyOut);
      calloc.free(subKeyPtr);
    }
  }

  StartupRunValueWriteResult _resultFromErrorStatus(int status) {
    if (status == ERROR_SUCCESS) {
      return const StartupRunValueWriteResult.success();
    }
    return switch (status) {
      ERROR_FILE_NOT_FOUND || ERROR_PATH_NOT_FOUND => const StartupRunValueWriteResult.notFound(),
      ERROR_ACCESS_DENIED => StartupRunValueWriteResult.accessDenied(status),
      _ => StartupRunValueWriteResult.failed(status),
    };
  }
}
