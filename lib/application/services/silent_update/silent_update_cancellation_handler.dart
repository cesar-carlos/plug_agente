import 'dart:developer' as developer;
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/service_update_pending_coordinator.dart';
import 'package:plug_agente/application/services/silent_update/update_transition_gate.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Completes a user-cancelled silent update cycle.
class SilentUpdateCancellationHandler {
  SilentUpdateCancellationHandler({
    required IPendingSilentUpdateStore pendingStore,
    required PersistentCircuitBreaker automaticFailureBreaker,
    required DateTime Function() clock,
    this.servicePending,
    this.launcherStatusReader,
  }) : _pendingStore = pendingStore,
       _automaticFailureBreaker = automaticFailureBreaker,
       _clock = clock;

  final ISilentUpdateLauncherStatusReader? launcherStatusReader;
  final IPendingSilentUpdateStore _pendingStore;
  final ServiceUpdatePendingCoordinator? servicePending;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final DateTime Function() _clock;

  Future<Result<SilentUpdateOutcome>> completeAutomaticCancellation({
    required String feedUrl,
    required String? checkId,
    required UpdateCheckDiagnostics? existingDiagnostics,
    required void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated,
    required Future<void> Function() persistDiagnostics,
  }) => UpdateTransitionGate.forStore(_pendingStore).run(() async {
    try {
      if (servicePending != null) {
        final result = await servicePending!.reconcile(cancel: true);
        if (result.isError()) return Failure(result.exceptionOrNull()!);
        final decision = result.getOrThrow().decision;
        if (decision == ServicePendingDecision.active || decision == ServicePendingDecision.attention) {
          return const Success(SilentUpdateOutcome.pendingInProgress);
        }
      } else {
        final pending = await _pendingStore.read();
        if (pending is PendingSilentUpdateDownloaded) {
          final status = await launcherStatusReader?.read(pending.launcherStatusPath);
          if (pending.launchedAt != null || status != null) {
            return const Success(SilentUpdateOutcome.pendingInProgress);
          }
        }
        await _pendingStore.clear();
      }
      await _automaticFailureBreaker.reset();
      final now = _clock();
      try {
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
      } on Object catch (error, stack) {
        developer.log('Cancellation diagnostics unavailable', error: error, stackTrace: stack);
      }
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.cancelled);
    } on Object catch (error) {
      return Failure(
        error is domain.Failure
            ? error
            : domain.ConfigurationFailure.withContext(
                message: 'Não foi possível confirmar o cancelamento. Verifique a recuperação.',
                cause: error,
                context: const {'reason': 'cancellation_unconfirmed', 'outcome_unknown': true},
              ),
      );
    }
  });
}
