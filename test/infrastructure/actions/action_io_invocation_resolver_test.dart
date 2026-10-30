import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_action_environment_resolver.dart';
import 'package:plug_agente/domain/actions/i_agent_operational_profile_resolver.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_io_invocation_resolver.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:result_dart/result_dart.dart';

class _Adapter extends Mock implements ExecutableActionAdapter {}

class _Environment extends Mock implements IActionEnvironmentResolver {}

class _Profile extends Mock implements IAgentOperationalProfileResolver {}

void main() {
  test('resolves saved invocation without changing arguments and rejects remote parameter injection', () async {
    final adapter = _Adapter();
    final env = _Environment();
    final profile = _Profile();
    const definition = AgentActionDefinition(
      id: 'a',
      name: 'Saved',
      config: ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: 'fixture.exe')),
    );
    const request = AgentActionExecutionRequest(actionId: 'a', source: AgentActionRequestSource.remoteHub);
    when(() => adapter.type).thenReturn(AgentActionType.executable);
    when(() => adapter.prepareExecution(definition: definition, request: request)).thenAnswer(
      (_) async => const Success(
        AgentActionPreparedExecution(
          actionType: AgentActionType.executable,
          redactedCommandPreview: 'fixture',
          workingDirectory: 'work',
        ),
      ),
    );
    when(() => adapter.resolveInvocationCommand(definition)).thenAnswer(
      (_) async => const Success(
        AgentActionCommandInvocation(
          executable: 'fixture.exe',
          arguments: ['literal argument'],
          runInShell: false,
          mode: ProcessStartMode.normal,
          redactedPreview: 'fixture',
          normalizedCommandLength: 10,
        ),
      ),
    );
    when(
      () => env.resolveForProcess(definition: definition, request: request),
    ).thenAnswer((_) async => const Success({'SAVED': 'value'}));
    when(() => profile.currentProfile).thenReturn('test');
    when(
      () => env.resolveIncludeParentEnvironment(policy: definition.policies.environment, operationalProfile: 'test'),
    ).thenReturn(false);
    final resolver = ActionIoInvocationResolver(AgentActionAdapterRegistry([adapter]), env, profile);
    final invocation = (await resolver.resolve(definition, request)).getOrThrow();
    expect(invocation.arguments, ['literal argument']);
    expect(invocation.workingDirectory, 'work');
    expect(invocation.environment, {'SAVED': 'value'});
    expect(invocation.includeParentEnvironment, isFalse);
    expect(
      (await resolver.resolve(definition, request.copyWith(runtimeParameters: {'command': 'injected'}))).isError(),
      isTrue,
    );
  });
}
