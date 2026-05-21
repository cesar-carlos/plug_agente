import 'package:plug_agente/domain/actions/action_enums.dart';

class AgentActionCapturedOutput {
  const AgentActionCapturedOutput({
    required this.text,
    required this.isCaptured,
    this.isTruncated = false,
  });

  final String text;
  final bool isCaptured;
  final bool isTruncated;

  static const disabled = AgentActionCapturedOutput(
    text: '',
    isCaptured: false,
  );
}

class AgentActionProcessResult {
  const AgentActionProcessResult({
    required this.status,
    required this.pid,
    required this.processStartedAt,
    required this.finishedAt,
    required this.stdout,
    required this.stderr,
    required this.redactionApplied,
    this.exitCode,
    this.processExecutable,
    this.processArgumentCount,
    this.processCommandPreview,
    this.contextHash,
    this.timedOut = false,
    this.killed = false,
    this.failureCode,
    this.failureMessage,
  });

  final AgentActionExecutionStatus status;
  final int pid;
  final int? exitCode;
  final DateTime processStartedAt;
  final DateTime finishedAt;
  final String? processExecutable;
  final int? processArgumentCount;
  final String? processCommandPreview;
  final AgentActionCapturedOutput stdout;
  final AgentActionCapturedOutput stderr;
  final String? contextHash;
  final bool timedOut;
  final bool killed;
  final bool redactionApplied;
  final String? failureCode;
  final String? failureMessage;

  bool get succeeded => status == AgentActionExecutionStatus.succeeded;
}

class AgentActionCancellationResult {
  const AgentActionCancellationResult({
    required this.executionId,
    required this.status,
    required this.killed,
    this.pid,
    this.message,
  });

  final String executionId;
  final AgentActionExecutionStatus status;
  final bool killed;
  final int? pid;
  final String? message;
}
