import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_action_definition_save_options.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';

/// Persists agent action definitions and reloads provider state on success.
final class AgentActionsSaveCoordinator {
  AgentActionsSaveCoordinator({
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required Future<void> Function() reload,
    required void Function(String? message) setErrorMessage,
  }) : _definitionsController = definitionsController,
       _executionsController = executionsController,
       _reload = reload,
       _setErrorMessage = setErrorMessage;

  final AgentActionsDefinitionsController _definitionsController;
  final AgentActionsExecutionsController _executionsController;
  final Future<void> Function() _reload;
  final void Function(String? message) _setErrorMessage;

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
    persist: (common) => _definitionsController.saveCommandLineAction(
      name: name,
      command: command,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      encodingPolicy: common.encodingPolicy,
      capturePolicy: common.capturePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveExecutableAction(
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      encodingPolicy: common.encodingPolicy,
      capturePolicy: common.capturePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveScriptAction(
      name: name,
      scriptPath: scriptPath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      interpreterPath: interpreterPath,
      workingDirectory: workingDirectory,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      encodingPolicy: common.encodingPolicy,
      capturePolicy: common.capturePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveJarAction(
      name: name,
      jarPath: jarPath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      javaExecutablePath: javaExecutablePath,
      workingDirectory: workingDirectory,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      encodingPolicy: common.encodingPolicy,
      capturePolicy: common.capturePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveEmailAction(
      name: name,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      subjectTemplate: subjectTemplate,
      bodyTemplate: bodyTemplate,
      actionId: actionId,
      description: description,
      cc: cc,
      bcc: bcc,
      attachmentPaths: attachmentPaths,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveComObjectAction(
      name: name,
      progId: progId,
      memberName: memberName,
      arguments: arguments,
      actionId: actionId,
      description: description,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
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
    persist: (common) => _definitionsController.saveDeveloperData7Action(
      name: name,
      executorPath: executorPath,
      projectPath: projectPath,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      actionId: actionId,
      description: description,
      data7ConfigPath: data7ConfigPath,
      state: common.state,
      notificationPolicy: common.notificationPolicy,
      retryPolicy: common.retryPolicy,
      timeoutPolicy: common.timeoutPolicy,
      environmentPolicy: common.environmentPolicy,
      exitCodePolicy: common.exitCodePolicy,
      processPolicy: common.processPolicy,
      lifecyclePolicy: common.lifecyclePolicy,
      remotePolicy: common.remotePolicy,
      elevatedPolicy: common.elevatedPolicy,
      contextPolicy: common.contextPolicy,
      pathChangePolicy: common.pathChangePolicy,
      encodingPolicy: common.encodingPolicy,
      capturePolicy: common.capturePolicy,
      queuePolicy: common.queuePolicy,
      pathPolicy: common.pathPolicy,
      canSave: canSave,
    ),
  );

  Future<bool> _saveDefinition({
    required AgentActionDefinitionSaveDelegate persist,
    AgentActionDefinitionSaveOptions options = const AgentActionDefinitionSaveOptions(),
  }) => _saveWithReload(() => persist(options));

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
