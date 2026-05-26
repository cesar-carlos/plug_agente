import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/com_object_action_runner.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_handler.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('ComObjectActionRunner', () {
    test(
      'should invoke registered handler and return succeeded process result',
      () async {
        final runner = ComObjectActionRunner(
          invocationRegistry: ComObjectInvocationRegistry(
            <RegisteredComObjectInvocation>[
              RegisteredComObjectInvocation(
                progId: 'AgentAction.Test',
                memberName: 'Ping',
                handler: _EchoComObjectHandler(),
              ),
            ],
          ),
        );

        final result = await runner.run(
          executionId: 'exec-1',
          definition: const AgentActionDefinition(
            id: 'action-1',
            name: 'Ping COM',
            state: AgentActionState.active,
            config: ComObjectActionConfig(
              progId: 'AgentAction.Test',
              memberName: 'Ping',
              arguments: <String, Object?>{'message': 'hello'},
            ),
          ),
          request: const AgentActionExecutionRequest(
            actionId: 'action-1',
            source: AgentActionRequestSource.localUi,
          ),
        );

        expect(result.isSuccess(), isTrue);
        final output = result.getOrThrow();
        expect(output.status, AgentActionExecutionStatus.succeeded);
        expect(output.stdout.text, contains('pong'));
      },
      skip: Platform.isWindows ? false : 'COM object runner tests require Windows',
    );
  });
}

class _EchoComObjectHandler extends ComObjectInvocationHandler {
  @override
  Future<Result<ComObjectInvocationResult>> invoke({
    required Map<String, Object?> arguments,
  }) async {
    return Success(
      ComObjectInvocationResult(
        summary: 'pong',
        details: arguments,
      ),
    );
  }
}
