import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:result_dart/result_dart.dart';

/// Completes a user-cancelled silent update cycle.
class SilentUpdateCancellationHandler {
  SilentUpdateCancellationHandler({
    required IPendingSilentUpdateStore pendingStore,
    required PersistentCircuitBreaker automaticFailureBreaker,
    required DateTime Function() clock,
  }) : _pendingStore = pendingStore,
       _automaticFailureBreaker = automaticFailureBreaker,
       _clock = clock;

  final IPendingSilentUpdateStore _pendingStore;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final DateTime Function() _clock;

  Future<Result<SilentUpdateOutcome>> completeAutomaticCancellation({
    required String feedUrl,
    required String? checkId,
    required UpdateCheckDiagnostics? existingDiagnostics,
    required void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated,
    required Future<void> Function() persistDiagnostics,
  }) async {
    await _pendingStore.clear();
    await _automaticFailureBreaker.reset();
    final now = _clock();
    onDiagnosticsUpdated(
      (existingDiagnostics ??
              UpdateCheckDiagnostics(
                checkedAt: now,
                configuredFeedUrl: feedUrl,
                requestedFeedUrl: feedUrl,
                checkId: checkId,
                currentVersion: AppConstants.appVersion,
              ))
          .copyWith(
            completedAt: now,
            completionSource: UpdateCheckCompletionSource.automaticCancelled,
            updateAvailable: false,
            errorMessage: 'Silent update cancelled because automatic silent updates were disabled',
          ),
    );
    await persistDiagnostics();
    return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.cancelled);
  }
}
