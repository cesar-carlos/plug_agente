import 'package:plug_agente/application/actions/agent_action_definition_persistence.dart';
import 'package:plug_agente/application/actions/agent_actions_definitions_save_host.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_action_definition_save_options.dart';

abstract interface class AgentActionSaveHandler {
  AgentActionType get actionType;
}

typedef AgentActionPoliciesFromOptions = ({
  AgentActionState state,
  AgentActionNotificationPolicy notificationPolicy,
  AgentActionRetryPolicy retryPolicy,
  AgentActionTimeoutPolicy timeoutPolicy,
  AgentActionEnvironmentPolicy environmentPolicy,
  AgentActionExitCodePolicy exitCodePolicy,
  AgentActionProcessPolicy processPolicy,
  AgentActionLifecyclePolicy lifecyclePolicy,
  AgentActionRemotePolicy remotePolicy,
  AgentActionElevatedPolicy elevatedPolicy,
  AgentActionContextPolicy? contextPolicy,
  AgentActionPathChangePolicy? pathChangePolicy,
  AgentActionEncodingPolicy encodingPolicy,
  AgentActionCapturePolicy capturePolicy,
  AgentActionQueuePolicy queuePolicy,
  AgentActionPathPolicy pathPolicy,
});

AgentActionPoliciesFromOptions policiesFromOptions(AgentActionDefinitionSaveOptions options) {
  return (
    state: options.state,
    notificationPolicy: options.notificationPolicy,
    retryPolicy: options.retryPolicy,
    timeoutPolicy: options.timeoutPolicy,
    environmentPolicy: options.environmentPolicy,
    exitCodePolicy: options.exitCodePolicy,
    processPolicy: options.processPolicy,
    lifecyclePolicy: options.lifecyclePolicy,
    remotePolicy: options.remotePolicy,
    elevatedPolicy: options.elevatedPolicy,
    contextPolicy: options.contextPolicy,
    pathChangePolicy: options.pathChangePolicy,
    encodingPolicy: options.encodingPolicy,
    capturePolicy: options.capturePolicy,
    queuePolicy: options.queuePolicy,
    pathPolicy: options.pathPolicy,
  );
}

final class CommandLineActionSaveHandler implements AgentActionSaveHandler {
  CommandLineActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.commandLine;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String command,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    String? workingDirectory,
  }) {
    return _persistence.saveCommandLineAction(
      host: host,
      name: name,
      command: command,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      encodingPolicy: policies.encodingPolicy,
      capturePolicy: policies.capturePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class ExecutableActionSaveHandler implements AgentActionSaveHandler {
  ExecutableActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.executable;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String executablePath,
    required List<String> arguments,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    String? workingDirectory,
  }) {
    return _persistence.saveExecutableAction(
      host: host,
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      encodingPolicy: policies.encodingPolicy,
      capturePolicy: policies.capturePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class ScriptActionSaveHandler implements AgentActionSaveHandler {
  ScriptActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.script;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String scriptPath,
    required List<String> arguments,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    String? interpreterPath,
    String? workingDirectory,
  }) {
    return _persistence.saveScriptAction(
      host: host,
      name: name,
      scriptPath: scriptPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      interpreterPath: interpreterPath,
      workingDirectory: workingDirectory,
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      encodingPolicy: policies.encodingPolicy,
      capturePolicy: policies.capturePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class JarActionSaveHandler implements AgentActionSaveHandler {
  JarActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.jar;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String jarPath,
    required List<String> arguments,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    String? javaExecutablePath,
    String? workingDirectory,
  }) {
    return _persistence.saveJarAction(
      host: host,
      name: name,
      jarPath: jarPath,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      javaExecutablePath: javaExecutablePath,
      workingDirectory: workingDirectory,
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      encodingPolicy: policies.encodingPolicy,
      capturePolicy: policies.capturePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class EmailActionSaveHandler implements AgentActionSaveHandler {
  EmailActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.email;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String smtpProfileId,
    required String from,
    required List<String> to,
    required String subjectTemplate,
    required String bodyTemplate,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    List<String> cc = const <String>[],
    List<String> bcc = const <String>[],
    List<AgentActionPathReference> attachmentPaths = const <AgentActionPathReference>[],
  }) {
    return _persistence.saveEmailAction(
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
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class ComObjectActionSaveHandler implements AgentActionSaveHandler {
  ComObjectActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.comObject;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
  }) {
    return _persistence.saveComObjectAction(
      host: host,
      name: name,
      progId: progId,
      memberName: memberName,
      arguments: arguments,
      canSave: canSave,
      actionId: actionId,
      description: description,
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class DeveloperData7ActionSaveHandler implements AgentActionSaveHandler {
  DeveloperData7ActionSaveHandler(this._persistence);

  final AgentActionDefinitionPersistence _persistence;

  @override
  AgentActionType get actionType => AgentActionType.developer;

  Future<bool> save({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String executorPath,
    required String projectPath,
    required String connectionId,
    required String connectionLabel,
    required bool canSave,
    required AgentActionPoliciesFromOptions policies,
    String? actionId,
    String? description,
    String? data7ConfigPath,
  }) {
    return _persistence.saveDeveloperData7Action(
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
      state: policies.state,
      notificationPolicy: policies.notificationPolicy,
      retryPolicy: policies.retryPolicy,
      timeoutPolicy: policies.timeoutPolicy,
      environmentPolicy: policies.environmentPolicy,
      exitCodePolicy: policies.exitCodePolicy,
      processPolicy: policies.processPolicy,
      lifecyclePolicy: policies.lifecyclePolicy,
      remotePolicy: policies.remotePolicy,
      elevatedPolicy: policies.elevatedPolicy,
      contextPolicy: policies.contextPolicy,
      pathChangePolicy: policies.pathChangePolicy,
      encodingPolicy: policies.encodingPolicy,
      capturePolicy: policies.capturePolicy,
      queuePolicy: policies.queuePolicy,
      pathPolicy: policies.pathPolicy,
    );
  }
}

final class AgentActionSaveHandlerRegistry {
  factory AgentActionSaveHandlerRegistry(AgentActionDefinitionPersistence persistence) {
    final commandLine = CommandLineActionSaveHandler(persistence);
    final executable = ExecutableActionSaveHandler(persistence);
    final script = ScriptActionSaveHandler(persistence);
    final jar = JarActionSaveHandler(persistence);
    final email = EmailActionSaveHandler(persistence);
    final comObject = ComObjectActionSaveHandler(persistence);
    final developerData7 = DeveloperData7ActionSaveHandler(persistence);
    return AgentActionSaveHandlerRegistry._(
      commandLine: commandLine,
      executable: executable,
      script: script,
      jar: jar,
      email: email,
      comObject: comObject,
      developerData7: developerData7,
      byType: {
        AgentActionType.commandLine: commandLine,
        AgentActionType.executable: executable,
        AgentActionType.script: script,
        AgentActionType.jar: jar,
        AgentActionType.email: email,
        AgentActionType.comObject: comObject,
        AgentActionType.developer: developerData7,
      },
    );
  }

  AgentActionSaveHandlerRegistry._({
    required this.commandLine,
    required this.executable,
    required this.script,
    required this.jar,
    required this.email,
    required this.comObject,
    required this.developerData7,
    required Map<AgentActionType, AgentActionSaveHandler> byType,
  }) : _byType = byType;

  final CommandLineActionSaveHandler commandLine;
  final ExecutableActionSaveHandler executable;
  final ScriptActionSaveHandler script;
  final JarActionSaveHandler jar;
  final EmailActionSaveHandler email;
  final ComObjectActionSaveHandler comObject;
  final DeveloperData7ActionSaveHandler developerData7;
  final Map<AgentActionType, AgentActionSaveHandler> _byType;

  AgentActionSaveHandler? handlerFor(AgentActionType type) => _byType[type];
}
