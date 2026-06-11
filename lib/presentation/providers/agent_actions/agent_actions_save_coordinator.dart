import 'package:plug_agente/application/actions/agent_action_definition_assembler.dart';
import 'package:plug_agente/application/actions/agent_action_definition_persistence.dart';
import 'package:plug_agente/application/actions/agent_action_definition_save_options.dart';
import 'package:plug_agente/application/actions/agent_action_save_handlers.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
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

  Future<bool> saveCommandLineAction({
    required String name,
    required String command,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.commandLine.save(
      host: _definitionsController,
      name: name,
      command: command,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      policies: common,
    ),
  );

  Future<bool> saveExecutableAction({
    required String name,
    required String executablePath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.executable.save(
      host: _definitionsController,
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      policies: common,
    ),
  );

  Future<bool> saveScriptAction({
    required String name,
    required String scriptPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? interpreterPath,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.script.save(
      host: _definitionsController,
      name: name,
      scriptPath: scriptPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      interpreterPath: interpreterPath,
      workingDirectory: workingDirectory,
      policies: common,
    ),
  );

  Future<bool> saveJarAction({
    required String name,
    required String jarPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? javaExecutablePath,
    String? workingDirectory,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.jar.save(
      host: _definitionsController,
      name: name,
      jarPath: jarPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      javaExecutablePath: javaExecutablePath,
      workingDirectory: workingDirectory,
      policies: common,
    ),
  );

  Future<bool> saveEmailAction({
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
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.email.save(
      host: _definitionsController,
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
      policies: common,
    ),
  );

  Future<bool> saveComObjectAction({
    required String name,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.comObject.save(
      host: _definitionsController,
      name: name,
      progId: progId,
      memberName: memberName,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      policies: common,
    ),
  );

  Future<bool> saveDeveloperData7Action({
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
  }) => _saveDefinition(
    options: options,
    persist: (common) => _handlers.developerData7.save(
      host: _definitionsController,
      name: name,
      executorPath: executorPath,
      projectPath: projectPath,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      canSave: canSave,
      actionId: actionId,
      description: description,
      data7ConfigPath: data7ConfigPath,
      policies: common,
    ),
  );

  Future<bool> _saveDefinition({
    required Future<bool> Function(AgentActionPoliciesFromOptions policies) persist,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveWithReload(() => persist(policiesFromOptions(options)));

  Future<bool> _saveWithReload(Future<bool> Function() save) async {
    _setErrorMessage(null);
    _definitionsController.lastOperationErrorMessage = null;
    _executionsController.clearTestStateForSelectionChange();
    final shouldReload = await save();
    if (shouldReload) {
      await _reload();
      return true;
    }
    return false;
  }
}
