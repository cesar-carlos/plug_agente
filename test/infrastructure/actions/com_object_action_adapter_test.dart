import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/com_object_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_handler.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('ComObjectActionAdapter', () {
    test('should validate saved definition when invocation is not registered', () async {
      final adapter = ComObjectActionAdapter(
        invocationRegistry: ComObjectInvocationRegistry(const <RegisteredComObjectInvocation>[]),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Future COM action',
          state: AgentActionState.active,
          config: ComObjectActionConfig(
            progId: 'Example.Prog',
            memberName: 'Execute',
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().canRun, isFalse);
    });

    test('should prepare execution when invocation is registered', () async {
      final adapter = ComObjectActionAdapter(
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

      final result = await adapter.prepareExecution(
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
      expect(result.getOrThrow().redactedCommandPreview, contains('[REDACTED]'));
    });

    test('should reject execution preflight when invocation is not registered', () async {
      final adapter = ComObjectActionAdapter(
        invocationRegistry: ComObjectInvocationRegistry(const <RegisteredComObjectInvocation>[]),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Missing handler',
          config: ComObjectActionConfig(
            progId: 'AgentAction.Test',
            memberName: 'Ping',
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
    });
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
