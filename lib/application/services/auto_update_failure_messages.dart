import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// Shared helper for the auto-update flow. Both the orchestrator and the
/// coordinator used to carry an identical private copy of this; centralise
/// it here so the surface stays small and consistent.
String extractAutoUpdateFailureMessage(Exception error) {
  if (error is domain.Failure) return error.message;
  return error.toString();
}

bool isAutoUpdateDeferral(Exception error) => error is domain.Failure &&
    (error.context['outcome_unknown'] == true ||
     error.context['retryable'] == true ||
     const {'maintenance_deferred', 'service_not_ready', 'service_operation_changed',
       'updater_unavailable', 'updater_ipc_failed', 'service_reconciliation_unknown',
       'application_recovery_cooldown', 'update_cancelled', 'cancellation_not_safe',
       'installation_in_progress', 'another_update_is_prepared', 'authorization_required'}.contains(error.context['reason']));
