import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/agent_action_get_execution_output_options.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';

void main() {
  group('resolveAgentActionGetExecutionOutputOptions', () {
    test('should hide output when include_output is false', () {
      final options = resolveAgentActionGetExecutionOutputOptions(
        params: const <String, dynamic>{
          'include_output': false,
          'stdout_offset': 10,
        },
        capturePolicy: const AgentActionCapturePolicy(
          
        ),
      );

      expect(options.exposeStdout, isFalse);
      expect(options.exposeStderr, isFalse);
    });

    test('should respect capture policy when client requests output', () {
      final options = resolveAgentActionGetExecutionOutputOptions(
        params: const <String, dynamic>{'include_output': true},
        capturePolicy: const AgentActionCapturePolicy(
          captureStderr: false,
        ),
      );

      expect(options.exposeStdout, isTrue);
      expect(options.exposeStderr, isFalse);
    });

    test('should resolve stdout cursor and legacy output_offset aliases', () {
      final options = resolveAgentActionGetExecutionOutputOptions(
        params: const <String, dynamic>{
          'stdout_cursor': 12,
          'stderr_cursor': 3,
          'output_offset': 99,
        },
      );

      expect(options.paging.stdoutOffsetUtf8, 12);
      expect(options.paging.stderrOffsetUtf8, 3);
    });

    test('should fall back to output_offset when stdout offset keys are absent', () {
      final options = resolveAgentActionGetExecutionOutputOptions(
        params: const <String, dynamic>{'output_offset': 40},
      );

      expect(options.paging.stdoutOffsetUtf8, 40);
    });
  });
}
