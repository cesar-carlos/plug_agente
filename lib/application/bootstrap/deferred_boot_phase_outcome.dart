/// Result of deferred bootstrap phases used to drive runtime guard transitions
/// and optional Hub auto-connect gating.
class DeferredBootPhaseOutcome {
  const DeferredBootPhaseOutcome({
    required this.schedulerStarted,
    required this.hadCriticalFailure,
  });

  const DeferredBootPhaseOutcome.success() : schedulerStarted = true, hadCriticalFailure = false;

  final bool schedulerStarted;
  final bool hadCriticalFailure;

  bool get agentActionsFullyReady => schedulerStarted && !hadCriticalFailure;

  /// Hub transport is independent of the agent-action scheduler; only skip
  /// auto-connect when deferred bootstrap failed with an unexpected error.
  bool get shouldSkipHubAutoConnect => hadCriticalFailure;
}
