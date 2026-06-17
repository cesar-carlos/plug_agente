import 'package:plug_agente/application/actions/agent_action_definition_assembler.dart';
import 'package:plug_agente/application/actions/agent_action_definition_persistence.dart';
import 'package:plug_agente/application/actions/agent_action_definition_save_options.dart';
import 'package:plug_agente/application/actions/agent_action_save_handlers.dart';
import 'package:plug_agente/application/actions/agent_actions_definitions_save_host.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Persists agent action definitions and reloads provider state on success.
final class AgentActionsSaveCoordinator {
  AgentActionsSaveCoordinator({
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required SaveAgentActionDefinition saveDefinition,
    required Uuid uuid,
    required DateTime Function() now,
    required String Function(Exception failure) messageFor,
    required Future<void> Function() reload,
    required void Function(String? message) setErrorMessage,
    AgentActionDefinitionAssembler assembler = const AgentActionDefinitionAssembler(),
  }) : _definitionsController = definitionsController,
       _executionsController = executionsController,
       _reload = reload,
       _setErrorMessage = setErrorMessage,
       _handlers = AgentActionSaveHandlerRegistry(
         AgentActionDefinitionPersistence(
           saveDefinition: saveDefinition,
           uuid: uuid,
           now: now,
           messageFor: messageFor,
           assembler: assembler,
         ),
       );

  final AgentActionsDefinitionsController _definitionsController;
  final AgentActionsExecutionsController _executionsController;
  final Future<void> Function() _reload;
  final void Function(String? message) _setErrorMessage;
  final AgentActionSaveHandlerRegistry _handlers;

  Future<Result<void>> saveCommandLineAction({
    required String name,
    required String command,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.commandLine.save(
      host: host,
      name: name,
      command: command,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      policies: policies,
    ),
  );

  Future<Result<void>> saveExecutableAction({
    required String name,
    required String executablePath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.executable.save(
      host: host,
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      policies: policies,
    ),
  );

  Future<Result<void>> saveScriptAction({
    required String name,
    required String scriptPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? interpreterPath,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.script.save(
      host: host,
      name: name,
      scriptPath: scriptPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      interpreterPath: interpreterPath,
      workingDirectory: workingDirectory,
      policies: policies,
    ),
  );

  Future<Result<void>> saveJarAction({
    required String name,
    required String jarPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? javaExecutablePath,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.jar.save(
      host: host,
      name: name,
      jarPath: jarPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      javaExecutablePath: javaExecutablePath,
      workingDirectory: workingDirectory,
      policies: policies,
    ),
  );

  Future<Result<void>> saveEmailAction({
    required String name,
    required String smtpProfileId,
    required String from,
    required List<String> to,
    required String subjectTemplate,
    required String bodyTemplate,
    required bool canSave,
    String? actionId,
    String? description,
    List<String> cc = const <String>[],
    List<String> bcc = const <String>[],
    List<AgentActionPathReference> attachmentPaths = const <AgentActionPathReference>[],
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.email.save(
      host: host,
      name: name,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      subjectTemplate: subjectTemplate,
      bodyTemplate: bodyTemplate,
      canSave: canSave,
      actionId: actionId,
      description: description,
      cc: cc,
      bcc: bcc,
      attachmentPaths: attachmentPaths,
      policies: policies,
    ),
  );

  Future<Result<void>> saveComObjectAction({
    required String name,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.comObject.save(
      host: host,
      name: name,
      progId: progId,
      memberName: memberName,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      policies: policies,
    ),
  );

  Future<Result<void>> saveDeveloperData7Action({
    required String name,
    required String executorPath,
    required String projectPath,
    required String connectionId,
    required String connectionLabel,
    required bool canSave,
    String? actionId,
    String? description,
    String? data7ConfigPath,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _persistDefinition(
    options: options,
    persist: (host, policies) => _handlers.developerData7.save(
      host: host,
      name: name,
      executorPath: executorPath,
      projectPath: projectPath,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      canSave: canSave,
      actionId: actionId,
      description: description,
      data7ConfigPath: data7ConfigPath,
      policies: policies,
    ),
  );

  Future<Result<void>> _persistDefinition({
    required Future<bool> Function(
      AgentActionsDefinitionsSaveHost host,
      AgentActionPoliciesFromOptions policies,
    )
    persist,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveWithReload(
    () => persist(_definitionsController, policiesFromOptions(options)),
  );

  Future<Result<void>> _saveWithReload(Future<bool> Function() save) async {
    _setErrorMessage(null);
    _definitionsController.lastOperationErrorMessage = null;
    _executionsController.clearTestStateForSelectionChange();
    final shouldReload = await save();
    if (shouldReload) {
      await _reload();
      return const Success(unit);
    }

    final message = _definitionsController.lastOperationErrorMessage?.trim();
    if (message != null && message.isNotEmpty) {
      final failure = domain.ValidationFailure(message);
      failure.log();
      _setErrorMessage(message);
      return Failure(failure);
    }

    final failure = domain.ValidationFailure('Agent action save was not performed');
    failure.log();
    return Failure(failure);
  }
}
