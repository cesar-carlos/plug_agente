import 'package:plug_agente/domain/actions/actions.dart';

/// Parsed elevated helper status file (redacted fields only).
class ElevatedActionStatusFile {
  const ElevatedActionStatusFile({
    required this.executionId,
    required this.status,
    required this.finishedAt,
    required this.redactionApplied,
    this.exitCode,
    this.failureCode,
    this.failureMessage,
    this.stdoutText,
    this.stderrText,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.processCommandPreview,
  });

  final String executionId;
  final AgentActionExecutionStatus status;
  final DateTime finishedAt;
  final bool redactionApplied;
  final int? exitCode;
  final String? failureCode;
  final String? failureMessage;
  final String? stdoutText;
  final String? stderrText;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final String? processCommandPreview;

  bool get isTerminal => status.isTerminal;
}
