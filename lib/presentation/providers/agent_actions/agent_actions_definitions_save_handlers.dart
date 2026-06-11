import 'package:plug_agente/application/actions/agent_action_definition_assembler.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:uuid/uuid.dart';

/// Mutable save-session state owned by the definitions controller
/// and passed into type-specific save handlers.
abstract interface class AgentActionsDefinitionsSaveHost {
  bool get isSaving;
  set isSaving(bool value);

  String? get lastOperationErrorMessage;
  set lastOperationErrorMessage(String? value);

  String? get selectedActionId;
  set selectedActionId(String? value);

  Map<String, String> get sessionPreflightSnapshotHashes;
  Map<String, DateTime> get sessionPreflightValidatedAt;

  void notifyStateChanged();
  AgentActionDefinition? existingDefinition(String? actionId);
}

/// Type-specific definition save handlers extracted from the definitions
/// controller to keep list/filter/preflight state separate from config assembly
/// and persistence.
final class AgentActionsDefinitionsSaveHandlers {
  AgentActionsDefinitionsSaveHandlers({
    required SaveAgentActionDefinition saveDefinition,
    required Uuid uuid,
    required DateTime Function() now,
    required String Function(Exception failure) messageFor,
    AgentActionDefinitionAssembler assembler = const AgentActionDefinitionAssembler(),
  }) : _saveDefinition = saveDefinition,
       _uuid = uuid,
       _now = now,
       _messageFor = messageFor,
       _assembler = assembler;

  final SaveAgentActionDefinition _saveDefinition;
  final Uuid _uuid;
  final DateTime Function() _now;
  final String Function(Exception failure) _messageFor;
  final AgentActionDefinitionAssembler _assembler;

  Future<bool> saveCommandLineAction({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String command,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    final trimmedWorkingDirectory = workingDirectory?.trim();
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: CommandLineActionConfig(
        command: command.trim(),
        workingDirectory: _assembler.optionalPathReference(trimmedWorkingDirectory, pathChangePolicy: pathChangePolicy),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveExecutableAction({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String executablePath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    final trimmedWorkingDirectory = workingDirectory?.trim();
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: ExecutableActionConfig(
        executablePath: _assembler.pathReference(executablePath.trim(), pathChangePolicy: pathChangePolicy),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: _assembler.optionalPathReference(trimmedWorkingDirectory, pathChangePolicy: pathChangePolicy),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveScriptAction({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String scriptPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? interpreterPath,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    final trimmedInterpreterPath = interpreterPath?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: ScriptActionConfig(
        scriptPath: _assembler.pathReference(scriptPath.trim(), pathChangePolicy: pathChangePolicy),
        interpreterPath: _assembler.optionalPathReference(trimmedInterpreterPath, pathChangePolicy: pathChangePolicy),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: _assembler.optionalPathReference(trimmedWorkingDirectory, pathChangePolicy: pathChangePolicy),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveJarAction({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String jarPath,
    required List<String> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    String? javaExecutablePath,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    final trimmedJavaPath = javaExecutablePath?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: JarActionConfig(
        jarPath: _assembler.pathReference(jarPath.trim(), pathChangePolicy: pathChangePolicy),
        javaExecutablePath: _assembler.optionalPathReference(trimmedJavaPath, pathChangePolicy: pathChangePolicy),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: _assembler.optionalPathReference(trimmedWorkingDirectory, pathChangePolicy: pathChangePolicy),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveEmailAction({
    required AgentActionsDefinitionsSaveHost host,
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
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: EmailActionConfig(
        smtpProfileId: smtpProfileId.trim(),
        from: from.trim(),
        to: List<String>.unmodifiable(to),
        cc: List<String>.unmodifiable(cc),
        bcc: List<String>.unmodifiable(bcc),
        subjectTemplate: subjectTemplate.trim(),
        bodyTemplate: bodyTemplate.trim(),
        attachmentPaths: List<AgentActionPathReference>.unmodifiable(attachmentPaths),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveComObjectAction({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
    required bool canSave,
    String? actionId,
    String? description,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: ComObjectActionConfig(
        progId: progId.trim(),
        memberName: memberName.trim(),
        arguments: Map<String, Object?>.unmodifiable(arguments),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> saveDeveloperData7Action({
    required AgentActionsDefinitionsSaveHost host,
    required String name,
    required String executorPath,
    required String projectPath,
    required String connectionId,
    required String connectionLabel,
    required bool canSave,
    String? actionId,
    String? description,
    String? data7ConfigPath,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) {
    final trimmedData7ConfigPath = data7ConfigPath?.trim() ?? '';
    final trimmedConnectionId = connectionId.trim();
    return _saveDraftDefinition(
      host: host,
      canSave: canSave,
      name: name,
      actionId: actionId,
      description: description,
      state: state,
      config: DeveloperActionConfig.data7Executor(
        executorPath: _assembler.pathReference(executorPath.trim()),
        projectPath: _assembler.pathReference(projectPath.trim()),
        data7ConfigPath: _assembler.pathReference(trimmedData7ConfigPath),
        connectionId: trimmedConnectionId,
        connectionLabel: connectionLabel.trim().isEmpty ? trimmedConnectionId : connectionLabel.trim(),
      ),
      buildPolicies: (existing) => _assembler.policiesForSave(
        existing: existing,
        notificationPolicy: notificationPolicy,
        retryPolicy: retryPolicy,
        timeoutPolicy: timeoutPolicy,
        environmentPolicy: environmentPolicy,
        exitCodePolicy: exitCodePolicy,
        processPolicy: processPolicy,
        lifecyclePolicy: lifecyclePolicy,
        remotePolicy: remotePolicy,
        elevatedPolicy: elevatedPolicy,
        contextPolicy: contextPolicy,
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
    );
  }

  Future<bool> _saveDraftDefinition({
    required AgentActionsDefinitionsSaveHost host,
    required bool canSave,
    required String name,
    required String? actionId,
    required String? description,
    required AgentActionState state,
    required AgentActionConfig config,
    required AgentActionDefinitionPolicies Function(AgentActionDefinition? existing) buildPolicies,
  }) async {
    if (!canSave) {
      return false;
    }

    host.isSaving = true;
    host.lastOperationErrorMessage = null;
    host.notifyStateChanged();

    final trimmedId = actionId?.trim();
    final trimmedDesc = description?.trim();
    final existing = host.existingDefinition(trimmedId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDesc == null || trimmedDesc.isEmpty ? null : trimmedDesc,
      state: state,
      config: config,
      policies: buildPolicies(existing),
      definitionVersion: existing?.definitionVersion ?? 1,
      lastPreflightSnapshotHash: _resolveLastPreflightSnapshotHash(host, existing),
      lastPreflightValidatedAt: _resolveLastPreflightValidatedAt(host, existing),
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    return _persistDefinition(host, definition);
  }

  Future<bool> _persistDefinition(
    AgentActionsDefinitionsSaveHost host,
    AgentActionDefinition definition,
  ) async {
    final result = await _saveDefinition(definition);
    var shouldReload = false;
    result.fold(
      (savedDefinition) {
        host.selectedActionId = savedDefinition.id;
        shouldReload = true;
      },
      (failure) {
        host.lastOperationErrorMessage = _messageFor(failure);
      },
    );

    host.isSaving = false;
    if (!shouldReload) {
      host.notifyStateChanged();
      return false;
    }

    return true;
  }

  String? _resolveLastPreflightSnapshotHash(
    AgentActionsDefinitionsSaveHost host,
    AgentActionDefinition? existing,
  ) {
    if (existing == null) {
      return null;
    }
    return host.sessionPreflightSnapshotHashes[existing.id] ?? existing.lastPreflightSnapshotHash;
  }

  DateTime? _resolveLastPreflightValidatedAt(
    AgentActionsDefinitionsSaveHost host,
    AgentActionDefinition? existing,
  ) {
    if (existing == null) {
      return null;
    }
    return host.sessionPreflightValidatedAt[existing.id] ?? existing.lastPreflightValidatedAt;
  }
}
