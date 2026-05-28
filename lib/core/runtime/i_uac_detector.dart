/// Detects whether installing an update on the current Windows machine
/// would require explicit user consent through a UAC elevation prompt.
///
/// The silent auto-update flow uses this signal to decide whether the
/// download + apply cycle can run end-to-end without a user being present.
/// When [requiresUserConsentForElevation] returns `true`, the coordinator
/// will probe for new versions but stop before downloading, surfacing an
/// "update available, requires admin" state for the UI to act on.
///
/// Conservative defaults apply: when detection cannot determine the OS
/// state (e.g., FFI calls fail, registry unreadable), implementations
/// should err on the side of "requires consent" so the agent never starts
/// an install that surprises the operator with an unexpected UAC prompt.
abstract interface class IUacDetector {
  /// Returns `true` when applying an update would trigger a UAC prompt
  /// for the current process. Two conditions must both hold:
  ///
  /// - The current process token is **not** elevated; and
  /// - The operating system has UAC enabled (registry `EnableLUA = 1`).
  ///
  /// Returns `false` when either condition is missing — meaning the
  /// install can elevate (or run as-is) without surprising the user.
  ///
  /// Outside Windows the method always returns `false`: there is no UAC
  /// to gate against, so the auto-update flow proceeds as before.
  bool requiresUserConsentForElevation();

  /// Resolves the richer detection state (elevation type + UAC enabled
  /// flag + whether consent is required). Used by diagnostics surfaces
  /// to explain *why* the gate triggered. The default implementation in
  /// concrete classes should remain a pure read on the same cached
  /// values [requiresUserConsentForElevation] uses, so callers can mix
  /// both APIs without paying for double FFI work.
  UacDetectionState detect();
}

/// Token elevation classification for the running process. Mirrors the
/// `TOKEN_ELEVATION_TYPE` enum from the Windows SDK so diagnostics can
/// distinguish "standard user", "split-token administrator" and "fully
/// elevated" without leaking Win32 enum values to the rest of the app.
enum UacElevationType {
  /// Token is the default; usually means the process is running as a
  /// standard (non-admin) user when UAC is on, or any user when UAC is
  /// off. Mapping from `TokenElevationTypeDefault`.
  defaultType,

  /// Token is the split-token administrator's *limited* view. UAC is
  /// enabled and the process is running without elevation; admin
  /// privileges sit on the unused linked token. Mapping from
  /// `TokenElevationTypeLimited`.
  limited,

  /// Token carries full administrative privileges. Either the user
  /// explicitly elevated the process or UAC is disabled and the user is
  /// an administrator. Mapping from `TokenElevationTypeFull`.
  full,

  /// Detection failed (FFI error or non-Windows platform). Diagnostics
  /// callers should treat this as "unknown" — the boolean gate still
  /// applies its conservative default.
  unknown,
}

/// Read-only snapshot returned by [IUacDetector.detect]. Diagnostics
/// surfaces use it to render an explanation; the boolean gate in the
/// coordinator continues to use [IUacDetector.requiresUserConsentForElevation]
/// which derives directly from these same fields.
class UacDetectionState {
  const UacDetectionState({
    required this.elevationType,
    required this.uacEnabled,
    required this.requiresConsent,
    this.detectionError,
  });

  /// Convenience constant for non-Windows platforms.
  static const UacDetectionState noop = UacDetectionState(
    elevationType: UacElevationType.unknown,
    uacEnabled: null,
    requiresConsent: false,
  );

  /// Snapshot used when detection failed mid-flight. The boolean gate
  /// defaults to "requires consent" so the auto-update flow does not
  /// surprise the operator with an unexpected UAC prompt.
  static const UacDetectionState failed = UacDetectionState(
    elevationType: UacElevationType.unknown,
    uacEnabled: null,
    requiresConsent: true,
    detectionError: 'detection_failed',
  );

  final UacElevationType elevationType;

  /// `true` when `EnableLUA = 1`, `false` when `EnableLUA = 0`, `null`
  /// when the value could not be read (e.g., key missing, Wow6432Node
  /// redirection, permission error).
  final bool? uacEnabled;

  /// Whether the silent auto-update gate must engage. Derived from
  /// `elevationType != full && uacEnabled == true`, with a fail-safe
  /// to `true` when detection is incomplete.
  final bool requiresConsent;

  /// Short tag describing the detection failure, when relevant. Free-
  /// form text — diagnostics surfaces should treat it as a label, not
  /// as a localized message.
  final String? detectionError;
}

/// Detector that never reports a UAC requirement. Used by tests and on
/// non-Windows platforms where elevation prompts do not apply.
class NoopUacDetector implements IUacDetector {
  const NoopUacDetector();

  @override
  bool requiresUserConsentForElevation() => false;

  @override
  UacDetectionState detect() => UacDetectionState.noop;
}
