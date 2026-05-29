import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart';

/// Result of running the agent profile save flow.
///
/// Modeled as a sealed class so the page can exhaust the relevant cases
/// without leaking the intermediate failure handling of the coordinator.
sealed class AgentProfileSaveOutcome {
  const AgentProfileSaveOutcome();
}

/// The profile was persisted locally but no Hub sync was attempted because
/// there is no access token, server URL, agent id, or the hub is offline.
final class AgentProfileSaveLocalOnly extends AgentProfileSaveOutcome {
  const AgentProfileSaveLocalOnly();
}

/// The profile was persisted locally and successfully synchronized with the
/// remote Hub (catalog version stored locally).
final class AgentProfileSaveSynced extends AgentProfileSaveOutcome {
  const AgentProfileSaveSynced();
}

/// The profile was persisted locally but the Hub PATCH failed.
final class AgentProfileSaveHubPartialFailure extends AgentProfileSaveOutcome {
  const AgentProfileSaveHubPartialFailure({
    required this.hubErrorMessage,
    required this.failure,
    required this.profile,
  });

  final String hubErrorMessage;
  final Failure failure;
  final AgentProfile profile;

  bool get canRetry => failure.isTransient || failure is ProfileVersionConflictFailure;

  bool get isVersionConflict => failure is ProfileVersionConflictFailure;
}

/// PATCH succeeded on the hub but storing the hub profile version locally failed.
final class AgentProfileSaveHubCatalogPersistFailure extends AgentProfileSaveOutcome {
  const AgentProfileSaveHubCatalogPersistFailure({
    required this.message,
    required this.profile,
  });

  final String message;
  final AgentProfile profile;
}

/// Saving the profile locally failed; nothing was sent to the Hub.
final class AgentProfileSaveLocalFailure extends AgentProfileSaveOutcome {
  const AgentProfileSaveLocalFailure({required this.errorMessage});

  final String errorMessage;
}

/// Profile fields were replaced from the hub catalog (reload flow).
final class AgentProfileSaveReloadedFromHub extends AgentProfileSaveOutcome {
  const AgentProfileSaveReloadedFromHub({required this.profile});

  final AgentProfile profile;
}
