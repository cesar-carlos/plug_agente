import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:win32/win32.dart';

/// Native Windows implementation of [IUacDetector] backed by Win32 FFI.
///
/// Caches the resolved state to avoid re-running FFI work on every
/// silent check. The default [cacheTtl] of `null` keeps the legacy
/// "cache for the entire process lifetime" behaviour because:
///
/// - the process elevation token cannot change in-process; and
/// - `EnableLUA` only takes effect after a reboot.
///
/// Callers that explicitly want to re-read the policy (e.g., long-lived
/// kiosks where IT may roll out a UAC policy change between sessions
/// without a forced reboot, or tests) can pass a finite [cacheTtl].
class WindowsUacDetector implements IUacDetector {
  WindowsUacDetector({
    this.cacheTtl,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String _logName = 'windows_uac_detector';

  /// Path under HKLM to the policy subkey that hosts `EnableLUA`. This
  /// is the canonical key Windows reads when deciding whether to run
  /// UAC. Group Policy refreshes it on logon; reading the 64-bit hive
  /// directly is the same signal Microsoft documents for IsUAC* helpers.
  static const String _uacPolicyPath = r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';
  static const String _uacValueName = 'EnableLUA';

  /// Time-to-live for the cached detection. `null` means "cache forever
  /// for the process lifetime" — the safe default since UAC config
  /// effectively requires a reboot to take effect.
  final Duration? cacheTtl;
  final DateTime Function() _clock;

  UacDetectionState? _cachedState;
  DateTime? _cachedAt;

  @override
  bool requiresUserConsentForElevation() => detect().requiresConsent;

  @override
  UacDetectionState detect() {
    final cached = _cachedState;
    final cachedAt = _cachedAt;
    if (cached != null && cachedAt != null) {
      final ttl = cacheTtl;
      if (ttl == null || _clock().difference(cachedAt) < ttl) {
        return cached;
      }
    }

    final resolved = _resolve();
    _cachedState = resolved;
    _cachedAt = _clock();
    return resolved;
  }

  UacDetectionState _resolve() {
    if (!Platform.isWindows) {
      return UacDetectionState.noop;
    }
    try {
      final elevationType = _resolveElevationType();
      final uacEnabled = _readEnableLua();
      // Conservative gate: requires consent unless we proved the token
      // is fully elevated, *or* we proved UAC is disabled. Any unknown
      // (FFI failure, registry unreadable) keeps the gate engaged.
      final consentNotNeeded = elevationType == UacElevationType.full || uacEnabled == false;
      final requiresConsent = !consentNotNeeded;
      developer.log(
        'UAC detector resolved: requiresConsent=$requiresConsent, '
        'elevationType=${elevationType.name}, uacEnabled=$uacEnabled',
        name: _logName,
        level: 800,
      );
      return UacDetectionState(
        elevationType: elevationType,
        uacEnabled: uacEnabled,
        requiresConsent: requiresConsent,
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'UAC detection failed; defaulting to requiresConsent=true',
        name: _logName,
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return UacDetectionState.failed;
    }
  }

  /// Reads the process token elevation type via
  /// `OpenProcessToken` + `GetTokenInformation(TokenElevationType)`.
  /// Falls back to [UacElevationType.unknown] on any FFI error.
  UacElevationType _resolveElevationType() {
    final hTokenOut = calloc<IntPtr>();
    try {
      final opened = OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, hTokenOut);
      if (opened == 0) {
        developer.log(
          'OpenProcessToken failed; cannot determine elevation type',
          name: _logName,
          level: 800,
        );
        return UacElevationType.unknown;
      }
      final hToken = hTokenOut.value;
      final elevationTypeOut = calloc<Uint32>();
      final returnedLength = calloc<Uint32>();
      try {
        final ok = GetTokenInformation(
          hToken,
          _tokenElevationTypeInfoClass,
          elevationTypeOut,
          sizeOf<Uint32>(),
          returnedLength,
        );
        if (ok == 0) {
          developer.log(
            'GetTokenInformation(TokenElevationType) failed',
            name: _logName,
            level: 800,
          );
          return UacElevationType.unknown;
        }
        return switch (elevationTypeOut.value) {
          1 => UacElevationType.defaultType,
          2 => UacElevationType.full,
          3 => UacElevationType.limited,
          _ => UacElevationType.unknown,
        };
      } finally {
        calloc.free(returnedLength);
        calloc.free(elevationTypeOut);
        CloseHandle(hToken);
      }
    } finally {
      calloc.free(hTokenOut);
    }
  }

  /// Reads `EnableLUA` from the **64-bit view** of the policy key by
  /// passing `KEY_WOW64_64KEY` to `RegOpenKeyEx`. Without this flag, a
  /// 32-bit process running on 64-bit Windows would be redirected to
  /// `SOFTWARE\Wow6432Node\...` where the value does not exist, and
  /// the detector would always default to "requires consent".
  ///
  /// Returns `true` when the value is `1`, `false` when `0`, and
  /// `null` when the value cannot be read.
  bool? _readEnableLua() {
    final subKeyPtr = _uacPolicyPath.toNativeUtf16();
    final valueNamePtr = _uacValueName.toNativeUtf16();
    final hKeyOut = calloc<IntPtr>();
    try {
      final openStatus = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        subKeyPtr,
        0,
        KEY_QUERY_VALUE | KEY_WOW64_64KEY,
        hKeyOut,
      );
      if (openStatus != ERROR_SUCCESS) {
        developer.log(
          'RegOpenKeyEx(EnableLUA) returned status=$openStatus; treating as unreadable',
          name: _logName,
          level: 800,
        );
        return null;
      }
      final hKey = hKeyOut.value;
      final dataOut = calloc<Uint8>(sizeOf<Uint32>());
      final dataSizeOut = calloc<Uint32>()..value = sizeOf<Uint32>();
      try {
        final queryStatus = RegQueryValueEx(
          hKey,
          valueNamePtr,
          nullptr,
          nullptr,
          dataOut,
          dataSizeOut,
        );
        if (queryStatus != ERROR_SUCCESS) {
          developer.log(
            'RegQueryValueEx(EnableLUA) returned status=$queryStatus; treating as unreadable',
            name: _logName,
            level: 800,
          );
          return null;
        }
        final dwordValue = dataOut.cast<Uint32>().value;
        return dwordValue != 0;
      } finally {
        calloc.free(dataSizeOut);
        calloc.free(dataOut);
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(hKeyOut);
      calloc.free(valueNamePtr);
      calloc.free(subKeyPtr);
    }
  }

  /// `TokenElevationType` constant from the `TOKEN_INFORMATION_CLASS`
  /// enum (== 18). Hard-coded next to its layout so the FFI call is
  /// self-contained.
  static const int _tokenElevationTypeInfoClass = 18;
}
