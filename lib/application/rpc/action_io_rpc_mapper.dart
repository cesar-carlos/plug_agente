import 'dart:convert';

import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';

abstract final class ActionIoRpcMapper {
  static Map<String, dynamic> execution(ActionIoExecutionSnapshot snapshot, {ActionIoSessionClaim? claim}) => {
    ...agentActionExecutionToGetExecutionResult(
      ActionIoExecutionProjection.fromSnapshot(snapshot).getOrThrow(),
      sanitizeForRemoteHub: true,
    ),
    'io': {
      'version': 1,
      'mode': 'faithful',
      'process_state': snapshot.processState,
      'stdin_state': snapshot.stdinState,
      'capture_state': snapshot.captureState,
      'output_expired': snapshot.outputExpired,
      'next_input_sequence': snapshot.nextInputSequence,
      if (claim?.initialMessageId != null) 'initial_message_id': claim!.initialMessageId,
      if (claim?.closeMessageId != null) 'close_message_id': claim!.closeMessageId,
    },
  };

  static Map<String, dynamic> receipt(ActionIoMessageReceipt value) => {
    'execution_id': value.executionId,
    'message_id': value.messageId,
    'sequence': value.sequence,
    'state': value.state.name,
    'confirmed_bytes': value.confirmedBytes,
    'next_input_sequence': value.nextInputSequence,
    'stdin_state': value.stdinState.name,
  };

  static Map<String, dynamic> page(String executionId, ActionIoReadPage page) => {
    'execution_id': executionId,
    'next_sequence': page.nextSequence,
    'terminal': page.terminal,
    'output_complete': page.outputComplete,
    'events': [
      for (final event in page.events)
        switch (event) {
          ActionIoOutputEvent() => {
            'sequence': event.sequence,
            'type': 'output',
            'stream': event.stream.name,
            'offset': event.offset,
            'data_base64': base64Encode(event.bytes),
          },
          ActionIoProcessExitedEvent() => {
            'sequence': event.sequence,
            'type': 'process_exited',
            'exit_code': event.exitCode,
          },
          ActionIoCompletedEvent() => {
            'sequence': event.sequence,
            'type': 'completed',
            'output_complete': event.outputComplete,
            if (event.failureCode != null)
              'failure': {
                'code': event.failureCode,
                'phase': 'capture',
                'origin': 'agent',
                'diagnostic_id': '$executionId:${event.sequence}',
                'effects_possible': true,
                'retryable': false,
                'recovery': 'Inspect the execution and retained output; do not replay automatically.',
              },
          },
        },
    ],
  };
}
