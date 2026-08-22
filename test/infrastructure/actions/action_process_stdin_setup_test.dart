import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'agent_action_process_runner_test_support.dart';

void main() {
  group('ActionProcessStdinSetup', () {
    test('should close stdin when injection mode is not stdin', () async {
      const setup = kTestActionProcessStdinSetup;
      final process = await Process.start(
        Platform.isWindows ? 'cmd.exe' : 'cat',
        Platform.isWindows ? ['/C', 'exit 0'] : [],
      );
      addTearDown(() async {
        if (process.pid != 0) {
          process.kill();
        }
      });

      final result = await setup.configure(
        process: process,
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
        actionId: 'action-1',
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should write runtime stdin payload when injection mode is stdin', () async {
      if (!Platform.isWindows) {
        return;
      }
      const setup = kTestActionProcessStdinSetup;
      final process = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-Command', r'$input | Out-String'],
      );
      addTearDown(() async {
        if (process.pid != 0) {
          process.kill();
        }
      });

      const payload = 'line-one\nline-two';
      final result = await setup.configure(
        process: process,
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'ignored'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              injectionMode: AgentActionContextInjectionMode.stdin,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            AgentActionProcessConstants.stdinRuntimeParameterKey: payload,
          },
        ),
        actionId: 'action-1',
      );

      expect(result.isSuccess(), isTrue);

      final stdout = await process.stdout.transform(utf8.decoder).join();
      await process.exitCode.timeout(const Duration(seconds: 15));

      expect(stdout, contains('line-one'));
      expect(stdout, contains('line-two'));
    });

    test('should fail when stdin mode has no runtime payload', () async {
      if (!Platform.isWindows) {
        return;
      }

      const setup = kTestActionProcessStdinSetup;
      final process = await Process.start(
        'cmd.exe',
        ['/C', 'exit 0'],
      );
      addTearDown(() async {
        process.kill();
      });

      final result = await setup.configure(
        process: process,
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              injectionMode: AgentActionContextInjectionMode.stdin,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
        actionId: 'action-1',
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.contextInjectionRequiresStdinPayloadReason),
      );
    });

    test('should fail when stdin write exceeds the IO timeout', () async {
      const setup = ActionProcessStdinSetup(
        secretPlaceholderResolver: AgentActionSecretPlaceholderResolver(),
        stdinIoTimeout: Duration(milliseconds: 20),
      );
      final process = _HangingStdinProcess();

      final result = await setup.configure(
        process: process,
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'ignored'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              injectionMode: AgentActionContextInjectionMode.stdin,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            AgentActionProcessConstants.stdinRuntimeParameterKey: 'payload',
          },
        ),
        actionId: 'action-1',
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionTimeoutFailure>());
      expect(
        (result.exceptionOrNull()! as ActionTimeoutFailure).code,
        AgentActionFailureCode.executionTimedOut,
      );
    });
  });
}

class _HangingStdinProcess implements Process {
  _HangingStdinProcess() : stdin = _HangingIOSink();

  @override
  final IOSink stdin;

  @override
  int get pid => 4242;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HangingIOSink implements IOSink {
  @override
  void add(List<int> data) {}

  @override
  Future<void> flush() => Completer<void>().future;

  @override
  Future<void> close() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
