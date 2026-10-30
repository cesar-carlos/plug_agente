import 'package:plug_agente/domain/actions/action_io_session_reference.dart';

/// Durable metadata only; binary output is read separately through its journal.
final class ActionIoExecutionSnapshot {
  const ActionIoExecutionSnapshot({
    required this.session,
    required this.idempotencyKey,
    required this.createdAt,
    required this.processState,
    required this.stdinState,
    required this.captureState,
    required this.outputExpired,
    this.nextInputSequence = 0,
    this.terminalAt,
    this.exitCode,
    this.failureCode,
  });

  final ActionIoSessionReference session;
  final String idempotencyKey;
  final DateTime createdAt;
  final String processState;
  final String stdinState;
  final String captureState;
  final bool outputExpired;
  final int nextInputSequence;
  final DateTime? terminalAt;
  final int? exitCode;
  final String? failureCode;
}
