import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows Startup Apps overlay for Run keys.
///
/// Path: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run`
/// A matching value name can keep a healthy Run entry from launching.
enum StartupApprovedStatus {
  /// No StartupApproved value for this name (Windows treats Run as allowed).
  notPresent,

  /// Explicitly allowed (typically status dword `0x02` or `0x06`).
  enabled,

  /// Blocked by Startup Apps / Task Manager (typically status dword `0x03`).
  disabled,

  /// Value exists but could not be classified (treat as blocked).
  unknown,

  accessDenied,
  failed,
}

class StartupApprovedReadResult {
  const StartupApprovedReadResult._(this.status, this.nativeStatus, this.rawBytes);

  const StartupApprovedReadResult.notPresent() : this._(StartupApprovedStatus.notPresent, null, null);

  const StartupApprovedReadResult.enabled([Uint8List? rawBytes])
    : this._(StartupApprovedStatus.enabled, null, rawBytes);

  const StartupApprovedReadResult.disabled([Uint8List? rawBytes])
    : this._(StartupApprovedStatus.disabled, null, rawBytes);

  const StartupApprovedReadResult.unknown([Uint8List? rawBytes])
    : this._(StartupApprovedStatus.unknown, null, rawBytes);

  const StartupApprovedReadResult.accessDenied(int nativeStatus)
    : this._(StartupApprovedStatus.accessDenied, nativeStatus, null);

  const StartupApprovedReadResult.failed(int nativeStatus)
    : this._(StartupApprovedStatus.failed, nativeStatus, null);

  final StartupApprovedStatus status;
  final int? nativeStatus;
  final Uint8List? rawBytes;

  bool get isEffectivelyEnabled =>
      status == StartupApprovedStatus.notPresent || status == StartupApprovedStatus.enabled;

  bool get isEffectivelyDisabled =>
      status == StartupApprovedStatus.disabled || status == StartupApprovedStatus.unknown;
}

enum StartupApprovedWriteStatus {
  success,
  accessDenied,
  failed,
}

class StartupApprovedWriteResult {
  const StartupApprovedWriteResult._(this.status, this.nativeStatus);

  const StartupApprovedWriteResult.success() : this._(StartupApprovedWriteStatus.success, null);

  const StartupApprovedWriteResult.accessDenied(int nativeStatus)
    : this._(StartupApprovedWriteStatus.accessDenied, nativeStatus);

  const StartupApprovedWriteResult.failed(int nativeStatus)
    : this._(StartupApprovedWriteStatus.failed, nativeStatus);

  final StartupApprovedWriteStatus status;
  final int? nativeStatus;
}

abstract interface class IStartupApprovedStore {
  StartupApprovedReadResult read({required String valueName});

  StartupApprovedWriteResult writeEnabled({required String valueName});
}

/// Classifies StartupApproved REG_BINARY payloads (locale-independent).
class StartupApprovedBinary {
  const StartupApprovedBinary._();

  /// Enabled marker used by Task Manager / Settings when re-enabling.
  static final Uint8List enabledPayload = Uint8List.fromList(const <int>[
    0x02,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);

  static StartupApprovedStatus classify(Uint8List bytes) {
    if (bytes.length < 4) {
      return StartupApprovedStatus.unknown;
    }
    final statusDword = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    return switch (statusDword) {
      0x02 || 0x06 => StartupApprovedStatus.enabled,
      0x03 => StartupApprovedStatus.disabled,
      _ => StartupApprovedStatus.unknown,
    };
  }
}

/// Reads/writes StartupApproved Run values through Win32 registry APIs.
class Win32StartupApprovedStore implements IStartupApprovedStore {
  const Win32StartupApprovedStore();

  static const String _subKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  @override
  StartupApprovedReadResult read({required String valueName}) {
    final subKeyPtr = _subKeyPath.toNativeUtf16();
    final hKeyOut = calloc<IntPtr>();
    try {
      final openStatus = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        KEY_QUERY_VALUE,
        hKeyOut,
      );
      if (openStatus != ERROR_SUCCESS) {
        return _readResultFromOpenStatus(openStatus);
      }
      final hKey = hKeyOut.value;
      try {
        return _readValue(hKey, valueName);
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(hKeyOut);
      calloc.free(subKeyPtr);
    }
  }

  @override
  StartupApprovedWriteResult writeEnabled({required String valueName}) {
    final subKeyPtr = _subKeyPath.toNativeUtf16();
    final hKeyOut = calloc<IntPtr>();
    try {
      final openStatus = RegCreateKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        nullptr,
        REG_OPTION_NON_VOLATILE,
        KEY_SET_VALUE,
        nullptr,
        hKeyOut,
        nullptr,
      );
      if (openStatus != ERROR_SUCCESS) {
        return _writeResultFromStatus(openStatus);
      }
      final hKey = hKeyOut.value;
      try {
        final valueNamePtr = valueName.toNativeUtf16();
        final payload = StartupApprovedBinary.enabledPayload;
        final dataPtr = calloc<Uint8>(payload.length);
        try {
          dataPtr.asTypedList(payload.length).setAll(0, payload);
          final status = RegSetValueEx(
            hKey,
            valueNamePtr,
            0,
            REG_BINARY,
            dataPtr,
            payload.length,
          );
          return _writeResultFromStatus(status);
        } finally {
          calloc.free(dataPtr);
          calloc.free(valueNamePtr);
        }
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(hKeyOut);
      calloc.free(subKeyPtr);
    }
  }

  StartupApprovedReadResult _readValue(int hKey, String valueName) {
    final valueNamePtr = valueName.toNativeUtf16();
    final dataSizeOut = calloc<Uint32>();
    try {
      final sizeStatus = RegQueryValueEx(hKey, valueNamePtr, nullptr, nullptr, nullptr, dataSizeOut);
      if (sizeStatus != ERROR_SUCCESS) {
        return _readResultFromQueryStatus(sizeStatus);
      }

      final dataSize = dataSizeOut.value;
      if (dataSize == 0) {
        return const StartupApprovedReadResult.unknown();
      }

      final typeOut = calloc<Uint32>();
      final dataOut = calloc<Uint8>(dataSize);
      try {
        dataSizeOut.value = dataSize;
        final readStatus = RegQueryValueEx(hKey, valueNamePtr, nullptr, typeOut, dataOut, dataSizeOut);
        if (readStatus != ERROR_SUCCESS) {
          return _readResultFromQueryStatus(readStatus);
        }
        if (typeOut.value != REG_BINARY) {
          return const StartupApprovedReadResult.unknown();
        }
        final bytes = Uint8List.fromList(dataOut.asTypedList(dataSizeOut.value));
        return switch (StartupApprovedBinary.classify(bytes)) {
          StartupApprovedStatus.enabled => StartupApprovedReadResult.enabled(bytes),
          StartupApprovedStatus.disabled => StartupApprovedReadResult.disabled(bytes),
          _ => StartupApprovedReadResult.unknown(bytes),
        };
      } finally {
        calloc.free(dataOut);
        calloc.free(typeOut);
      }
    } finally {
      calloc.free(dataSizeOut);
      calloc.free(valueNamePtr);
    }
  }

  StartupApprovedReadResult _readResultFromOpenStatus(int status) {
    return switch (status) {
      ERROR_FILE_NOT_FOUND || ERROR_PATH_NOT_FOUND => const StartupApprovedReadResult.notPresent(),
      ERROR_ACCESS_DENIED => StartupApprovedReadResult.accessDenied(status),
      _ => StartupApprovedReadResult.failed(status),
    };
  }

  StartupApprovedReadResult _readResultFromQueryStatus(int status) {
    return switch (status) {
      ERROR_FILE_NOT_FOUND || ERROR_PATH_NOT_FOUND => const StartupApprovedReadResult.notPresent(),
      ERROR_ACCESS_DENIED => StartupApprovedReadResult.accessDenied(status),
      _ => StartupApprovedReadResult.failed(status),
    };
  }

  StartupApprovedWriteResult _writeResultFromStatus(int status) {
    if (status == ERROR_SUCCESS) {
      return const StartupApprovedWriteResult.success();
    }
    return switch (status) {
      ERROR_ACCESS_DENIED => StartupApprovedWriteResult.accessDenied(status),
      _ => StartupApprovedWriteResult.failed(status),
    };
  }
}
