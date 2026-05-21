import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_adapter.dart';

void main() {
  group('JarActionAdapter', () {
    test('should validate active jar definition with default java', () async {
      final adapter = JarActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Apps\job.jar',
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(
              originalPath: r'C:\Apps\job.jar',
            ),
            arguments: <String>['--spring.profiles.active=prod'],
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().redactedDiagnostics, containsPair('uses_default_java', true));
    });

    test('should reject missing jar file during definition validation', () async {
      final adapter = JarActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => false,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Missing jar',
          config: JarActionConfig(
            jarPath: AgentActionPathReference(
              originalPath: r'C:\Missing\job.jar',
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionPathContextConstants.fileNotFoundReason),
      );
    });

    test('should prepare execution with redacted preview', () async {
      final adapter = JarActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          directoryExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Apps\job.jar',
          canonicalizeDirectory: (_) async => r'C:\Apps',
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Jar job',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(
              originalPath: r'C:\Apps\job.jar',
            ),
            arguments: <String>['secret-token'],
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final prepared = result.getOrThrow();
      expect(prepared.redactedCommandPreview, contains('job.jar'));
      expect(prepared.redactedCommandPreview, isNot(contains('secret-token')));
    });
  });
}
