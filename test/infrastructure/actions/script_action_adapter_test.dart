import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_script_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';

void main() {
  group('ScriptActionAdapter', () {
    test('should validate active script definition with default interpreter', () async {
      final adapter = ScriptActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Jobs\daily.ps1',
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Daily script',
          state: AgentActionState.active,
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(
              originalPath: r'C:\Jobs\daily.ps1',
            ),
            arguments: <String>['-Verbose'],
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().redactedDiagnostics, containsPair('uses_default_interpreter', true));
      expect(result.getOrThrow().redactedDiagnostics, containsPair('script_extension', '.ps1'));
    });

    test('should reject missing script file during definition validation', () async {
      final adapter = ScriptActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => false,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Missing script',
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(
              originalPath: r'C:\Missing\daily.ps1',
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
      final adapter = ScriptActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          directoryExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Jobs\daily.ps1',
          canonicalizeDirectory: (_) async => r'C:\Jobs',
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Script job',
          state: AgentActionState.active,
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(
              originalPath: r'C:\Jobs\daily.ps1',
            ),
            arguments: <String>['token'],
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final prepared = result.getOrThrow();
      expect(prepared.redactedCommandPreview, contains('daily.ps1'));
      expect(prepared.redactedCommandPreview, isNot(contains('token')));
    });

    test('should reject batch script when interpreter is not cmd.exe', () async {
      final adapter = ScriptActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (path) async => path,
          fileLength: (_) async => 1,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Wrong interpreter',
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(
              originalPath: r'C:\Jobs\daily.bat',
            ),
            interpreterPath: AgentActionPathReference(
              originalPath: r'C:\Python\python.exe',
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionScriptConstants.unsupportedInterpreterForScriptReason),
      );
    });
  });
}
