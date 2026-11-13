import 'package:plug_agente/domain/actions/action_io_lifecycle.dart';

/// Metadata-only view of faithful execution; never contains stream payloads.
final class ActionIoExecutionStatus {
  const ActionIoExecutionStatus({
    required this.processState,
    required this.stdinState,
    required this.captureState,
    required this.outputExpired,
    this.admittedInputBytes = 0,
    this.confirmedInputBytes = 0,
    this.stdoutBytes = 0,
    this.stderrBytes = 0,
    this.lifecycle = const ActionIoLifecycle(),
  });

  final String processState;
  final String stdinState;
  final String captureState;
  final bool outputExpired;
  final int admittedInputBytes;
  final int confirmedInputBytes;
  final int stdoutBytes;
  final int stderrBytes;
  final ActionIoLifecycle lifecycle;
}
