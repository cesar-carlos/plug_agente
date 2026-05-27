import 'package:plug_agente/core/services/update_check_diagnostics.dart';

/// Pushes a non-sensitive subset of [UpdateCheckDiagnostics] to the Plug
/// hub after every auto-update cycle. The contract is documented in
/// `docs/communication/socket_communication_standard.md` under the
/// `agent.autoUpdate.diagnostics.push` method.
///
/// Implementations MUST:
/// - throttle to 1 request per minute (drop oldest, do not queue);
/// - never include sensitive paths (`installerPath`, `launcherPath`,
///   `installerLogPath`, `launcherStatusPath`, `installDirectory`,
///   `actualSha256`);
/// - truncate `errorMessage` to 1024 chars.
abstract interface class IAutoUpdateDiagnosticsGateway {
  /// Sends [diagnostics] tagged with the given [source]. Returns silently
  /// even if the hub is unreachable; failures must not break the
  /// auto-update flow (telemetry is best-effort).
  Future<void> push({
    required UpdateCheckDiagnostics diagnostics,
    required AutoUpdateDiagnosticsSource source,
  });
}

/// Discriminates which cycle produced the diagnostics. Mirrors
/// `source` in the schema.
enum AutoUpdateDiagnosticsSource {
  manual,
  background,
  silent,
  reconcile;

  /// Serialisable wire identifier.
  String get wireValue => switch (this) {
    AutoUpdateDiagnosticsSource.manual => 'manual',
    AutoUpdateDiagnosticsSource.background => 'background',
    AutoUpdateDiagnosticsSource.silent => 'silent',
    AutoUpdateDiagnosticsSource.reconcile => 'reconcile',
  };
}
