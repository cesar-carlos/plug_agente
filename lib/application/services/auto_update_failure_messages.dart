import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// Shared helper for the auto-update flow. Both the orchestrator and the
/// coordinator used to carry an identical private copy of this; centralise
/// it here so the surface stays small and consistent.
String extractAutoUpdateFailureMessage(Exception error) {
  if (error is domain.Failure) return error.message;
  return error.toString();
}
