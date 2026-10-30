import 'dart:typed_data';

import 'package:plug_agente/domain/actions/action_io.dart';

sealed class ActionIoEvent {
  const ActionIoEvent(this.sequence);
  final int sequence;
}

final class ActionIoProcessExitedEvent extends ActionIoEvent {
  const ActionIoProcessExitedEvent(super.sequence, this.exitCode);
  final int? exitCode;
}

final class ActionIoCompletedEvent extends ActionIoEvent {
  const ActionIoCompletedEvent(super.sequence, {required this.outputComplete, this.failureCode});
  final bool outputComplete;
  final String? failureCode;
}

final class ActionIoOutputEvent extends ActionIoEvent {
  ActionIoOutputEvent({required int sequence, required this.stream, required this.offset, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
      super(sequence);
  final ActionIoStream stream;
  final int offset;
  final Uint8List bytes;
}

final class ActionIoReadPage {
  ActionIoReadPage({
    required List<ActionIoEvent> events,
    required this.nextSequence,
    required this.terminal,
    required this.outputComplete,
  }) : events = List.unmodifiable(events);
  final List<ActionIoEvent> events;
  final int nextSequence;
  final bool terminal;
  final bool outputComplete;
}
