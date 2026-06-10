import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// Sealed root for failures produced by the silent update install path.
///
/// Lets the coordinator pattern-match on the concrete variant
/// (`is SilentInstallCancellationFailure`) instead of probing the magic
/// string keyed by [SilentInstallFailureContext.cancellationKey] on the
/// generic `Failure.context` map. The context entry is still written
/// for diagnostics breadcrumbs and backward compatibility with operators
/// reading the on-disk failure payload.
sealed class SilentInstallFailure extends domain.Failure {
  SilentInstallFailure.withContext({
    required super.message,
    required super.defaultCode,
    super.cause,
    super.context,
  }) : super.withContext();
}

/// User-driven cancellation (operator disabled automatic silent updates
/// mid-flight, or the coordinator forwarded a cancel signal between
/// download chunks). Not a fault: never trips the failure cooldown.
final class SilentInstallCancellationFailure extends SilentInstallFailure {
  SilentInstallCancellationFailure({
    required super.message,
    super.cause,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) : super.withContext(
         defaultCode: 'SILENT_UPDATE_CANCELLED',
         context: <String, dynamic>{
           ...context,
           SilentInstallFailureContext.cancellationKey: true,
         },
       );
}

/// Holds the small constants exchanged between the installer (writes
/// breadcrumbs into `Failure.context`) and the coordinator (reads them
/// for diagnostics). Kept separate so callers do not need to import the
/// installer just to inspect a failure.
abstract final class SilentInstallFailureContext {
  /// Context key marking a cancellation. Preserved for compatibility
  /// with operators inspecting persisted diagnostics; new code should
  /// rely on `failure is SilentInstallCancellationFailure` instead.
  static const String cancellationKey = 'cancelled';
}
