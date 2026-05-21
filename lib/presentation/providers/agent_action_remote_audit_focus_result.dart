/// Outcome of correlating a remote audit row with the local execution history panel.
enum AgentActionRemoteAuditFocusResult {
  succeeded,
  featureDisabled,
  missingActionId,
  executionNotResolvable,
  runtimeInstanceMismatch,
}
