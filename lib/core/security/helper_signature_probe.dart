import 'dart:async';
import 'dart:io';

/// Outcome of probing the Authenticode signature of a Windows binary
/// (typically `plug_update_helper.exe`).
enum HelperSignatureStatus {
  /// Authenticode chain validates against a trusted root.
  valid,

  /// File is signed but the chain does not validate (tampered, revoked,
  /// expired without timestamping, etc.).
  invalid,

  /// File is not signed at all.
  unsigned,

  /// Probe could not run (PowerShell missing, file missing, timeout).
  unknown,
}

/// Probes the Authenticode signature of a local Windows binary. Used to gate
/// the silent update helper before launch when
/// `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true`. Implementations must never
/// block the silent flow indefinitely — they enforce a short timeout and
/// return [HelperSignatureStatus.unknown] when measurement is impossible.
abstract interface class IHelperSignatureProbe {
  Future<HelperSignatureStatus> probe(String filePath);
}

/// Runs PowerShell `Get-AuthenticodeSignature` to verify Windows
/// Authenticode. Results are cached per session because the helper binary
/// does not change between checks within the same process lifetime, and
/// each PowerShell launch costs ~150 ms of cold start.
class PowerShellHelperSignatureProbe implements IHelperSignatureProbe {
  PowerShellHelperSignatureProbe({
    Duration timeout = const Duration(seconds: 5),
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Duration timeout,
    })? processRunner,
  }) : _timeout = timeout,
       _processRunner = processRunner ?? _defaultRunner;

  final Duration _timeout;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    Duration timeout,
  }) _processRunner;

  final Map<String, HelperSignatureStatus> _cache = <String, HelperSignatureStatus>{};

  @override
  Future<HelperSignatureStatus> probe(String filePath) async {
    final cached = _cache[filePath];
    if (cached != null) return cached;

    if (!Platform.isWindows) {
      return _cache[filePath] = HelperSignatureStatus.unknown;
    }
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      return _cache[filePath] = HelperSignatureStatus.unknown;
    }

    try {
      final result = await _processRunner(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          // Trailing whitespace + `Trim()` keeps the output a single token so
          // the parser stays simple even if PowerShell ever adds extras.
          "(Get-AuthenticodeSignature -FilePath '$filePath').Status",
        ],
        timeout: _timeout,
      );
      final status = _interpretStatus(result.stdout.toString().trim());
      return _cache[filePath] = status;
    } on TimeoutException {
      return _cache[filePath] = HelperSignatureStatus.unknown;
    } on ProcessException {
      return _cache[filePath] = HelperSignatureStatus.unknown;
    }
  }

  static HelperSignatureStatus _interpretStatus(String value) {
    // Authenticode SignatureStatus values per Microsoft docs:
    // - Valid: chain validated.
    // - NotSigned / Incompatible: file has no signature.
    // - HashMismatch / NotTrusted / UnknownError / NotSupportedFileFormat:
    //   chain failed.
    return switch (value) {
      'Valid' => HelperSignatureStatus.valid,
      'NotSigned' || 'Incompatible' => HelperSignatureStatus.unsigned,
      'HashMismatch' ||
      'NotTrusted' ||
      'UnknownError' ||
      'NotSupportedFileFormat' => HelperSignatureStatus.invalid,
      _ => HelperSignatureStatus.unknown,
    };
  }

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return Process.run(executable, arguments).timeout(timeout);
  }
}

/// Static probe used in non-Windows tests / DI overrides. Always returns
/// [HelperSignatureStatus.unknown] so callers fall back to best-effort
/// behavior (the helper still launches when `requireValidSignature=false`).
class NoOpHelperSignatureProbe implements IHelperSignatureProbe {
  const NoOpHelperSignatureProbe();

  @override
  Future<HelperSignatureStatus> probe(String filePath) async {
    return HelperSignatureStatus.unknown;
  }
}
