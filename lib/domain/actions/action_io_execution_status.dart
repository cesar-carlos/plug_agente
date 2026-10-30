/// Metadata-only view of faithful execution; never contains stream payloads.
final class ActionIoExecutionStatus {
  const ActionIoExecutionStatus({
    required this.processState,
    required this.stdinState,
    required this.captureState,
    required this.outputExpired,
  });

  final String processState;
  final String stdinState;
  final String captureState;
  final bool outputExpired;
}
