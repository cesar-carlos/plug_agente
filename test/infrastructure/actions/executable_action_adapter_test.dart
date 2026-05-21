import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_executable_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';

void main() {
  group('ExecutableActionAdapter', () {
    test('should validate active executable definition', () async {
      final adapter = ExecutableActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Tools\job.exe',
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run job',
          state: AgentActionState.active,
          config: ExecutableActionConfig(
            executablePath: AgentActionPathReference(
              originalPath: r'C:\Tools\job.exe',
            ),
            arguments: <String>['--mode', 'daily'],
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().canRun, isTrue);
      expect(
        result.getOrThrow().redactedDiagnostics,
        containsPair('argument_count', 2),
      );
    });

    test('should reject missing executable file during definition validation', () async {
      final adapter = ExecutableActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => false,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Missing executable',
          config: ExecutableActionConfig(
            executablePath: AgentActionPathReference(
              originalPath: r'C:\Missing\job.exe',
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.fileNotFoundReason),
      );
    });

    test('should reject disallowed executable extension', () async {
      final adapter = ExecutableActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Tools\job.ps1',
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Script executable',
          config: ExecutableActionConfig(
            executablePath: AgentActionPathReference(
              originalPath: r'C:\Tools\job.ps1',
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure, isA<ActionValidationFailure>());
      expect(
        failure.context,
        containsPair('reason', AgentActionPathContextConstants.fileExtensionNotAllowedReason),
      );
      expect(
        failure.context['allowed_extensions'],
        AgentActionExecutableConstants.allowedExecutableExtensions.toList(growable: false),
      );
    });

    test('should prepare execution with redacted preview', () async {
      final adapter = ExecutableActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          directoryExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Tools\job.exe',
          canonicalizeDirectory: (_) async => r'C:\Jobs',
          fileLength: (_) async => 1,
          launchAccessValidator:
              ({
                required String actionId,
                required String field,
                required String path,
                required String phase,
              }) => null,
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Executable job',
          state: AgentActionState.active,
          config: ExecutableActionConfig(
            executablePath: AgentActionPathReference(
              originalPath: r'C:\Tools\job.exe',
            ),
            arguments: <String>['--secret', 'token'],
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final prepared = result.getOrThrow();
      expect(
        prepared.redactedCommandPreview,
        r'C:\Tools\job.exe [REDACTED_ARG_0] [REDACTED_ARG_1]',
      );
      expect(prepared.redactedCommandPreview, isNot(contains('token')));
      expect(prepared.workingDirectory, r'C:\Jobs');
    });
  });
}
