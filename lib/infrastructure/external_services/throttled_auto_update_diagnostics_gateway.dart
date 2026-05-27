import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_auto_update_diagnostics_gateway.dart';

/// Function signature for the underlying transport call. Implementations
/// usually wrap the Socket.IO RPC client. Returns a future that completes
/// when the hub acknowledged the notification (or threw).
typedef AutoUpdateDiagnosticsPushTransport =
    Future<void> Function(Map<String, dynamic> payload);

/// Throttled gateway that pushes a non-sensitive subset of the diagnostics
/// to the hub at most once per minute. Sits between the orchestrator/
/// coordinator and the actual transport so the rate-limit logic is shared
/// across both manual and silent paths.
///
/// Privacy contract: only the fields enumerated in
/// [_buildPushPayload] are sent. Everything else stays local.
class ThrottledAutoUpdateDiagnosticsGateway implements IAutoUpdateDiagnosticsGateway {
  ThrottledAutoUpdateDiagnosticsGateway({
    required AutoUpdateDiagnosticsPushTransport transport,
    required String agentId,
    DateTime Function()? clock,
    Duration minimumInterval = const Duration(minutes: 1),
  }) : _transport = transport,
       _agentId = agentId,
       _clock = clock ?? DateTime.now,
       _minimumInterval = minimumInterval;

  final AutoUpdateDiagnosticsPushTransport _transport;
  final String _agentId;
  final DateTime Function() _clock;
  final Duration _minimumInterval;

  DateTime? _lastPushAt;

  /// Visible to tests so they can assert "next push respected the window".
  DateTime? get lastPushAt => _lastPushAt;

  @override
  Future<void> push({
    required UpdateCheckDiagnostics diagnostics,
    required AutoUpdateDiagnosticsSource source,
  }) async {
    final now = _clock();
    final lastPushAt = _lastPushAt;
    if (lastPushAt != null && now.difference(lastPushAt) < _minimumInterval) {
      // Drop silently. Telemetry is best-effort; preventing log spam
      // matters more than capturing every cycle.
      return;
    }

    final payload = _buildPushPayload(
      diagnostics: diagnostics,
      source: source,
      agentId: _agentId,
    );

    try {
      await _transport(payload);
      _lastPushAt = now;
    } on Exception catch (error, stackTrace) {
      // Hub unreachable / RPC error: do not propagate so the auto-update
      // cycle is not influenced by telemetry availability.
      developer.log(
        'Auto-update diagnostics push failed (best-effort)',
        name: 'auto_update_diagnostics_gateway',
        level: 800,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Builds the payload as defined in
/// `docs/communication/schemas/auto_update_diagnostics.schema.json`.
/// Sensitive fields (paths, hashes, full URLs) are intentionally omitted.
/// Visible for testing.
Map<String, dynamic> _buildPushPayload({
  required UpdateCheckDiagnostics diagnostics,
  required AutoUpdateDiagnosticsSource source,
  required String agentId,
}) {
  final probeDurationMs = diagnostics.triggerStartedAt != null && diagnostics.triggerCompletedAt != null
      ? diagnostics.triggerCompletedAt!.difference(diagnostics.triggerStartedAt!).inMilliseconds
      : null;
  final errorMessage = diagnostics.errorMessage;
  return <String, dynamic>{
    'agentId': agentId,
    'appVersion': diagnostics.currentVersion ?? '',
    'checkId': diagnostics.checkId,
    'checkedAt': diagnostics.checkedAt.toUtc().toIso8601String(),
    'source': source.wireValue,
    'completionSource': diagnostics.completionSource?.name,
    'remoteVersion': diagnostics.remoteVersion,
    'updateAvailable': diagnostics.updateAvailable,
    'channel': diagnostics.rolloutChannel,
    'rolloutBucket': diagnostics.rolloutBucket,
    'feedSignatureStatus': diagnostics.feedSignatureStatus,
    'feedSignatureRequired': diagnostics.feedSignatureRequired,
    'helperSignatureStatus': diagnostics.helperSignatureStatus,
    'probeDurationMs': probeDurationMs,
    'downloadDurationMs': null,
    'automaticFailureCount': diagnostics.automaticFailureCount,
    'errorMessage': errorMessage == null
        ? null
        : (errorMessage.length > 1024 ? errorMessage.substring(0, 1024) : errorMessage),
  };
}

/// Visible for tests.
Map<String, dynamic> buildAutoUpdateDiagnosticsPushPayload({
  required UpdateCheckDiagnostics diagnostics,
  required AutoUpdateDiagnosticsSource source,
  required String agentId,
}) {
  return _buildPushPayload(
    diagnostics: diagnostics,
    source: source,
    agentId: agentId,
  );
}
