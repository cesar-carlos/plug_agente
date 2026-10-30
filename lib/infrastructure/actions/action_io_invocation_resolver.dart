import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_action_environment_resolver.dart';
import 'package:plug_agente/domain/actions/i_agent_operational_profile_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';
import 'package:result_dart/result_dart.dart';

/// Resolves local executable metadata only. Remote bytes never enter adapters.
final class ActionIoInvocationResolver implements IActionIoInvocationResolver {
  const ActionIoInvocationResolver(this._adapters, this._environment, this._profile);
  final AgentActionAdapterRegistry _adapters;
  final IActionEnvironmentResolver _environment;
  final IAgentOperationalProfileResolver _profile;

  @override
  Future<Result<ActionIoInvocation>> resolve(
    AgentActionDefinition definition,
    AgentActionExecutionRequest request,
  ) async {
    if (request.actionId != definition.id ||
        request.runtimeParameters.isNotEmpty ||
        request.contextPath != null ||
        definition.policies.elevated.runElevated) {
      return _unsupported();
    }
    final resolved = _adapters.resolve(definition.type);
    if (resolved.isError()) return Failure(resolved.exceptionOrNull()!);
    final adapter = resolved.getOrThrow();
    if (adapter is! ExecutableActionAdapter &&
        adapter is! ScriptActionAdapter &&
        adapter is! JarActionAdapter &&
        adapter is! DeveloperData7ActionAdapter) {
      return _unsupported();
    }
    final prepared = await adapter.prepareExecution(definition: definition, request: request);
    if (prepared.isError()) return Failure(prepared.exceptionOrNull()!);
    final invocation = await switch (adapter) {
      ExecutableActionAdapter() => adapter.resolveInvocationCommand(definition),
      ScriptActionAdapter() => adapter.resolveInvocationCommand(definition),
      JarActionAdapter() => adapter.resolveInvocationCommand(definition),
      DeveloperData7ActionAdapter() => adapter.resolveInvocationCommand(definition),
      _ => throw StateError('Unsupported adapter'),
    };
    if (invocation.isError()) return Failure(invocation.exceptionOrNull()!);
    final command = invocation.getOrThrow();
    if (command.runInShell) return _unsupported();
    final environment = await _environment.resolveForProcess(definition: definition, request: request);
    if (environment.isError()) return Failure(environment.exceptionOrNull()!);
    return Success(
      ActionIoInvocation(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: prepared.getOrThrow().workingDirectory,
        environment: environment.getOrThrow(),
        includeParentEnvironment: _environment.resolveIncludeParentEnvironment(
          policy: definition.policies.environment,
          operationalProfile: _profile.currentProfile,
        ),
      ),
    );
  }

  Result<ActionIoInvocation> _unsupported() => Failure(
    ActionValidationFailure.withContext(
      message: 'The saved invocation is incompatible with faithful I/O.',
      code: 'ACTION_IO_EXECUTOR_UNSUPPORTED',
    ),
  );
}
