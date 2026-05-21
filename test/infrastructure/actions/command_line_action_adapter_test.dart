import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/command_line_action_adapter.dart';

void main() {
  group('CommandLineActionAdapter', () {
    final adapter = CommandLineActionAdapter();

    test('should validate active command line definition', () async {
      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'List files',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir | findstr txt'),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().canRun, isTrue);
      expect(
        result.getOrThrow().redactedDiagnostics,
        containsPair('command_length', 17),
      );
    });

    test('should reject empty command', () async {
      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Invalid command',
          config: CommandLineActionConfig(command: '   '),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).context, containsPair('field', 'command'));
    });

    test('should reject missing working directory during definition validation', () async {
      final adapter = CommandLineActionAdapter(
        pathValidator: ActionPathValidator(
          directoryExists: (_) async => false,
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Command with working directory',
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Missing',
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.directoryNotFoundReason),
      );
    });

    test('should reject working directory outside allowlist during definition validation', () async {
      final adapter = CommandLineActionAdapter(
        pathValidator: ActionPathValidator(
          directoryExists: (_) async => true,
          canonicalizeDirectory: (path) async {
            return switch (path) {
              r'C:\Jobs' => r'C:\Jobs',
              r'C:\Allowed' => r'C:\Allowed',
              _ => path,
            };
          },
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Restricted command',
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
            ),
          ),
          policies: AgentActionDefinitionPolicies(
            path: AgentActionPathPolicy(
              allowedWorkingDirectories: {r'C:\Allowed'},
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.workingDirectoryNotAllowedReason),
      );
    });

    test('should normalize working directory metadata for persisted definition', () async {
      final validatedAt = DateTime.utc(2026, 5, 15, 12, 30);
      final adapter = CommandLineActionAdapter(
        now: () => validatedAt,
        pathValidator: ActionPathValidator(
          directoryExists: (_) async => true,
          canonicalizeDirectory: (_) async => r'C:\Canonical\Jobs',
        ),
      );

      final result = await adapter.normalizeDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Canonical command',
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
            ),
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow().config as CommandLineActionConfig;
      expect(config.workingDirectory?.originalPath, r'C:\Jobs');
      expect(config.workingDirectory?.canonicalPath, r'C:\Canonical\Jobs');
      expect(config.workingDirectory?.existsAtValidation, isTrue);
      expect(config.workingDirectory?.validatedAt, validatedAt);
    });

    test('should prepare execution with redacted command preview', () async {
      final adapter = CommandLineActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          directoryExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Temp\context.json',
          canonicalizeDirectory: (_) async => r'C:\Data7',
          fileLength: (_) async => 2,
          readText: (_) async => '{}',
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Secret command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: r'echo ${secret:token} | findstr ok',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Data7',
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          contextPath: r'C:\Temp\context.json',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final prepared = result.getOrThrow();
      expect(prepared.redactedCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(prepared.redactedCommandPreview, isNot(contains('secret')));
      expect(prepared.workingDirectory, r'C:\Data7');
      expect(prepared.redactedDiagnostics, containsPair('context_path_extension', '.json'));
    });

    test('should reject context extension outside action policy', () async {
      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Restricted command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              allowedContextExtensions: {'.json'},
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          contextPath: r'C:\Temp\context.txt',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure, isA<ActionValidationFailure>());
      expect(failure.context, containsPair('reason', AgentActionPathContextConstants.contextExtensionNotAllowedReason));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
    });

    test('should reject preflight when working directory changed after save', () async {
      final adapter = CommandLineActionAdapter(
        pathValidator: ActionPathValidator(
          directoryExists: (_) async => true,
          canonicalizeDirectory: (_) async => r'C:\Current\Jobs',
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command with drift',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
              canonicalPath: r'C:\Saved\Jobs',
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.pathSnapshotMismatch);
      expect(failure.context, containsPair('reason', AgentActionPathContextConstants.pathChangedAfterSaveReason));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
    });
  });
}
