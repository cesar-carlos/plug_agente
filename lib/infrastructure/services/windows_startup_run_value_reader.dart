import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_environment_string_expander.dart';
import 'package:win32/win32.dart';

enum StartupRunValueReadStatus {
  found,
  notFound,
  accessDenied,
  failed,
}

/// Result of reading one startup Run value from the Windows registry.
///
/// Statuses come from numeric Win32 codes instead of parsing localized
/// `reg.exe` output, so classification is locale independent.
class StartupRunValueReadResult {
  const StartupRunValueReadResult._(this.status, this.value, this.nativeStatus);

  const StartupRunValueReadResult.found(String value) : this._(StartupRunValueReadStatus.found, value, null);

  const StartupRunValueReadResult.notFound() : this._(StartupRunValueReadStatus.notFound, null, null);

  const StartupRunValueReadResult.accessDenied(int nativeStatus)
    : this._(StartupRunValueReadStatus.accessDenied, null, nativeStatus);

  const StartupRunValueReadResult.failed(int nativeStatus)
    : this._(StartupRunValueReadStatus.failed, null, nativeStatus);

  final StartupRunValueReadStatus status;
  final String? value;
  final int? nativeStatus;
}

abstract interface class IStartupRunValueRegistryReader {
  StartupRunValueReadResult read({
    required StartupRegistryScope scope,
    required String valueName,
  });
}

typedef RegistryEnvironmentExpander = String Function(String value);

/// Reads Run values through `RegOpenKeyEx`/`RegQueryValueEx` (Win32 FFI).
class Win32StartupRunValueRegistryReader implements IStartupRunValueRegistryReader {
  const Win32StartupRunValueRegistryReader({
    RegistryEnvironmentExpander? environmentExpander,
  }) : _environmentExpander = environmentExpander ?? expandWindowsEnvironmentStrings;

  static const String _runSubKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

  final RegistryEnvironmentExpander _environmentExpander;

  @override
  StartupRunValueReadResult read({
    required StartupRegistryScope scope,
    required String valueName,
  }) {
    final rootKey = scope == StartupRegistryScope.currentUser ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
    final samDesired = switch (scope) {
      StartupRegistryScope.currentUser => KEY_QUERY_VALUE,
      StartupRegistryScope.localMachine => REG_SAM_FLAGS(KEY_QUERY_VALUE | KEY_WOW64_64KEY),
      StartupRegistryScope.localMachineWow6432 => REG_SAM_FLAGS(KEY_QUERY_VALUE | KEY_WOW64_32KEY),
    };

    final subKeyPtr = _runSubKeyPath.toPcwstr();
    final hKeyOut = calloc<Pointer>();
    try {
      final openStatus = RegOpenKeyEx(
        rootKey,
        subKeyPtr,
        0,
        samDesired,
        hKeyOut,
      );
      if (openStatus != ERROR_SUCCESS) {
        return _resultFromErrorStatus(openStatus);
      }
      final hKey = HKEY(hKeyOut.value);
      try {
        return _readValue(hKey, valueName);
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(hKeyOut);
      free(subKeyPtr);
    }
  }

  StartupRunValueReadResult _readValue(HKEY hKey, String valueName) {
    final valueNamePtr = valueName.toPcwstr();
    final dataSizeOut = calloc<Uint32>();
    try {
      final sizeStatus = RegQueryValueEx(hKey, valueNamePtr, nullptr, nullptr, dataSizeOut);
      if (sizeStatus != ERROR_SUCCESS) {
        return _resultFromErrorStatus(sizeStatus);
      }

      final dataSize = dataSizeOut.value;
      if (dataSize == 0) {
        return const StartupRunValueReadResult.found('');
      }

      final typeOut = calloc<Uint32>();
      // +2 guards against values stored without a UTF-16 null terminator.
      final dataOut = calloc<Uint8>(dataSize + 2);
      try {
        dataSizeOut.value = dataSize;
        final readStatus = RegQueryValueEx(hKey, valueNamePtr, typeOut, dataOut, dataSizeOut);
        if (readStatus != ERROR_SUCCESS) {
          return _resultFromErrorStatus(readStatus);
        }
        if (typeOut.value != REG_SZ && typeOut.value != REG_EXPAND_SZ) {
          // A non-string Run value cannot launch anything; surface it as an
          // unparsable entry so the repair flow rewrites it.
          return const StartupRunValueReadResult.found('');
        }
        final rawValue = dataOut.cast<Utf16>().toDartString();
        if (typeOut.value == REG_EXPAND_SZ) {
          return StartupRunValueReadResult.found(_environmentExpander(rawValue));
        }
        return StartupRunValueReadResult.found(rawValue);
      } finally {
        calloc.free(dataOut);
        calloc.free(typeOut);
      }
    } finally {
      calloc.free(dataSizeOut);
      free(valueNamePtr);
    }
  }

  StartupRunValueReadResult _resultFromErrorStatus(int status) {
    return switch (status) {
      ERROR_FILE_NOT_FOUND || ERROR_PATH_NOT_FOUND => const StartupRunValueReadResult.notFound(),
      ERROR_ACCESS_DENIED => StartupRunValueReadResult.accessDenied(status),
      _ => StartupRunValueReadResult.failed(status),
    };
  }
}
