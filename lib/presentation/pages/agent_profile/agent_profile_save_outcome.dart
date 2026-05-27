/// Result of running the agent profile save flow.
///
/// Modeled as a sealed class so the page can exhaust the relevant cases
/// without leaking the intermediate failure handling of the coordinator.
sealed class AgentProfileSaveOutcome {
  const AgentProfileSaveOutcome();
}

/// The profile was persisted locally but no Hub sync was attempted because
/// there is no access token, server URL or agent id available.
final class AgentProfileSaveLocalOnly extends AgentProfileSaveOutcome {
  const AgentProfileSaveLocalOnly();
}

/// The profile was persisted locally and successfully synchronized with the
/// remote Hub.
final class AgentProfileSaveSynced extends AgentProfileSaveOutcome {
  const AgentProfileSaveSynced();
}

/// The profile was persisted locally but the Hub PATCH failed. The user
/// should be informed that the data will be pushed on the next connection.
final class AgentProfileSaveHubPartialFailure extends AgentProfileSaveOutcome {
  const AgentProfileSaveHubPartialFailure({required this.hubErrorMessage});

  final String hubErrorMessage;
}

/// Saving the profile locally failed; nothing was sent to the Hub.
final class AgentProfileSaveLocalFailure extends AgentProfileSaveOutcome {
  const AgentProfileSaveLocalFailure({required this.errorMessage});

  final String errorMessage;
}
