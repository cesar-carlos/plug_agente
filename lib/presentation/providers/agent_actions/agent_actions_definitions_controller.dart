import 'dart:collection';

import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_preflight_validity.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_save_handlers.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_filter_helpers.dart';
import 'package:uuid/uuid.dart';

typedef AgentActionsDefinitionsStateChanged = void Function();

class AgentActionsDefinitionsController implements AgentActionsDefinitionsSaveHost {
  AgentActionsDefinitionsController({
    required SaveAgentActionDefinition saveDefinition,
    required DeleteAgentActionDefinition deleteDefinition,
    required ListDeveloperData7Connections listDeveloperData7Connections,
    required Uuid uuid,
    required String Function(Exception failure) messageFor,
    required AgentActionsDefinitionsStateChanged onStateChanged,
    AgentActionDefinitionSnapshotter definitionSnapshotter = const AgentActionDefinitionSnapshotter(),
    AgentActionPreflightSettings? preflightSettings,
    DateTime Function()? now,
    AgentActionsDefinitionsSaveHandlers? saveHandlers,
  }) : _saveDefinition = saveDefinition,
       _deleteDefinition = deleteDefinition,
       _listDeveloperData7Connections = listDeveloperData7Connections,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged,
       _definitionSnapshotter = definitionSnapshotter,
       _preflightSettings = preflightSettings,
       _now = now ?? DateTime.now,
       _saveHandlers =
           saveHandlers ??
           AgentActionsDefinitionsSaveHandlers(
             saveDefinition: saveDefinition,
             uuid: uuid,
             now: now ?? DateTime.now,
             messageFor: messageFor,
           );

  final SaveAgentActionDefinition _saveDefinition;
  final DeleteAgentActionDefinition _deleteDefinition;
  final ListDeveloperData7Connections _listDeveloperData7Connections;
  final String Function(Exception failure) _messageFor;
  final AgentActionsDefinitionsStateChanged _onStateChanged;
  final AgentActionDefinitionSnapshotter _definitionSnapshotter;
  final AgentActionPreflightSettings? _preflightSettings;
  final DateTime Function() _now;
  final AgentActionsDefinitionsSaveHandlers _saveHandlers;

  @override
  void notifyStateChanged() => _onStateChanged();

  @override
  final Map<String, String> sessionPreflightSnapshotHashes = <String, String>{};
  @override
  final Map<String, DateTime> sessionPreflightValidatedAt = <String, DateTime>{};

  List<AgentActionDefinition> definitions = <AgentActionDefinition>[];
  @override
  String? selectedActionId;
  AgentActionType? definitionTypeFilter;
  AgentActionState? definitionStateFilter;
  String definitionSearchQuery = '';
  @override
  bool isSaving = false;
  bool isDeleting = false;
  bool isLoadingDeveloperConnections = false;
  int _developerConnectionReloadGeneration = 0;
  List<DeveloperData7ConnectionOption> developerConnections = <DeveloperData7ConnectionOption>[];
  String? developerConnectionLookupMessage;
  String? resolvedDeveloperData7ConfigPath;
  bool usedDefaultDeveloperData7ConfigPath = false;
  @override
  String? lastOperationErrorMessage;

  UnmodifiableListView<AgentActionDefinition>? definitionsViewCache;
  List<AgentActionDefinition>? filteredDefinitionsCache;
  UnmodifiableListView<DeveloperData7ConnectionOption>? developerConnectionsViewCache;

  UnmodifiableListView<AgentActionDefinition> get definitionsView =>
      definitionsViewCache ??= UnmodifiableListView<AgentActionDefinition>(definitions);

  UnmodifiableListView<DeveloperData7ConnectionOption> get developerConnectionsView =>
      developerConnectionsViewCache ??= UnmodifiableListView<DeveloperData7ConnectionOption>(developerConnections);

  void invalidateCaches() {
    definitionsViewCache = null;
    developerConnectionsViewCache = null;
    filteredDefinitionsCache = null;
  }

  bool get hasDefinitionListFilters =>
      definitionTypeFilter != null || definitionStateFilter != null || definitionSearchQuery.isNotEmpty;

  AgentActionDefinition? get selectedDefinition {
    final selectedId = selectedActionId;
    if (selectedId == null) {
      return definitions.firstOrNull;
    }
    return definitions.where((definition) => definition.id == selectedId).firstOrNull;
  }

  @override
  AgentActionDefinition? existingDefinition(String? actionId) {
    if (actionId == null || actionId.isEmpty) {
      return null;
    }
    return definitions.where((definition) => definition.id == actionId).firstOrNull;
  }

  List<AgentActionDefinition> filteredDefinitions() {
    final cached = filteredDefinitionsCache;
    if (cached != null) {
      return cached;
    }

    final matched = definitions
        .where(
          (definition) => agentActionsMatchesDefinitionListFilter(
            definition: definition,
            typeFilter: definitionTypeFilter,
            stateFilter: definitionStateFilter,
            searchQuery: definitionSearchQuery,
          ),
        )
        .toList(growable: false);
    final selectedId = selectedActionId;
    if (selectedId == null) {
      return filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
    }
    if (matched.any((definition) => definition.id == selectedId)) {
      return filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
    }
    final selected = existingDefinition(selectedId);
    if (selected == null) {
      return filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
    }
    return filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(<AgentActionDefinition>[
      selected,
      ...matched,
    ]);
  }

  void setDefinitionTypeFilter(AgentActionType? type) {
    if (definitionTypeFilter == type) {
      return;
    }
    definitionTypeFilter = type;
    invalidateCaches();
    _onStateChanged();
  }

  void setDefinitionStateFilter(AgentActionState? state) {
    if (definitionStateFilter == state) {
      return;
    }
    definitionStateFilter = state;
    invalidateCaches();
    _onStateChanged();
  }

  void setDefinitionSearchQuery(String query) {
    final normalized = query.trim();
    if (definitionSearchQuery == normalized) {
      return;
    }
    definitionSearchQuery = normalized;
    invalidateCaches();
    _onStateChanged();
  }

  void clearDefinitionFilters() {
    if (!hasDefinitionListFilters) {
      return;
    }
    definitionTypeFilter = null;
    definitionStateFilter = null;
    definitionSearchQuery = '';
    invalidateCaches();
    _onStateChanged();
  }

  void applyRestoredFilters({
    required AgentActionType? definitionType,
    required AgentActionState? definitionState,
    required String definitionSearch,
  }) {
    final normalizedDefinitionSearch = definitionSearch.trim();
    final didChange =
        definitionTypeFilter != definitionType ||
        definitionStateFilter != definitionState ||
        definitionSearchQuery != normalizedDefinitionSearch;

    if (!didChange) {
      return;
    }

    definitionTypeFilter = definitionType;
    definitionStateFilter = definitionState;
    definitionSearchQuery = normalizedDefinitionSearch;
    invalidateCaches();
    _onStateChanged();
  }

  String? resolveSelectedActionId() {
    final selectedId = selectedActionId;
    if (selectedId != null && definitions.any((definition) => definition.id == selectedId)) {
      return selectedId;
    }
    if (definitions.isEmpty) {
      return null;
    }
    return definitions.first.id;
  }

  void replaceDefinitions(List<AgentActionDefinition> loaded) {
    definitions = loaded;
    invalidateCaches();
  }

  void syncSessionPreflightSnapshotHashes({
    required bool Function(AgentActionDefinition definition) isPreflightValid,
  }) {
    sessionPreflightSnapshotHashes.clear();
    sessionPreflightValidatedAt.clear();
    for (final definition in definitions) {
      if (!isPreflightValid(definition)) {
        continue;
      }

      final hash = definition.lastPreflightSnapshotHash;
      final validatedAt = definition.lastPreflightValidatedAt;
      if (hash != null && hash.isNotEmpty && validatedAt != null) {
        sessionPreflightSnapshotHashes[definition.id] = hash;
        sessionPreflightValidatedAt[definition.id] = validatedAt;
      }
    }
  }

  int get preflightValidityDays =>
      _preflightSettings?.validityDays ?? AgentActionPolicyDefaults.preflightValidityDuration.inDays;

  bool get hasPreflightPersistedOverride => _preflightSettings?.hasPersistedOverride ?? false;

  bool isPreflightValidForDefinition(AgentActionDefinition definition) {
    final recordedPreflightHash = sessionPreflightSnapshotHashes[definition.id] ?? definition.lastPreflightSnapshotHash;
    final recordedPreflightValidatedAt =
        sessionPreflightValidatedAt[definition.id] ?? definition.lastPreflightValidatedAt;

    return AgentActionPreflightValidity.isValid(
      recordedHash: recordedPreflightHash,
      expectedHash: preflightContentSnapshotHash(definition),
      lastValidatedAt: recordedPreflightValidatedAt,
      now: _now(),
      settings: _preflightSettings,
    );
  }

  bool isPreflightExpiredForDefinition(AgentActionDefinition definition) {
    final recordedPreflightHash = sessionPreflightSnapshotHashes[definition.id] ?? definition.lastPreflightSnapshotHash;
    final expectedHash = preflightContentSnapshotHash(definition);
    if (recordedPreflightHash == null || recordedPreflightHash != expectedHash) {
      return false;
    }

    final recordedPreflightValidatedAt =
        sessionPreflightValidatedAt[definition.id] ?? definition.lastPreflightValidatedAt;
    return !AgentActionPreflightValidity.isTimestampValid(
      recordedPreflightValidatedAt,
      now: _now(),
      settings: _preflightSettings,
    );
  }

  DateTime? preflightExpiresAtForDefinition(AgentActionDefinition definition) {
    final recordedPreflightValidatedAt =
        sessionPreflightValidatedAt[definition.id] ?? definition.lastPreflightValidatedAt;
    return AgentActionPreflightValidity.expiresAt(recordedPreflightValidatedAt, settings: _preflightSettings);
  }

  bool canSetDefinitionActive(String? actionId, {required bool draftModified}) {
    if (draftModified || actionId == null || actionId.trim().isEmpty) {
      return false;
    }

    final definition = existingDefinition(actionId);
    if (definition == null) {
      return false;
    }

    return isPreflightValidForDefinition(definition);
  }

  bool canSaveAction({required bool isFeatureEnabled}) => isFeatureEnabled && !isSaving;

  bool canDeleteDefinition({
    required AgentActionDefinition definition,
    required bool isFeatureEnabled,
    required bool hasActiveExecution,
  }) {
    if (!isFeatureEnabled || isDeleting) {
      return false;
    }
    return !hasActiveExecution;
  }

  void selectAction(String actionId) {
    if (selectedActionId == actionId) {
      return;
    }
    selectedActionId = actionId;
    invalidateCaches();
    _onStateChanged();
  }

  void clearSelectedAction() {
    selectedActionId = null;
    invalidateCaches();
  }

  Future<({bool shouldReload, String? errorMessage})> deleteSelectedAction({
    required AgentActionDefinition definition,
    required bool canDelete,
  }) async {
    if (!canDelete) {
      return (shouldReload: false, errorMessage: null);
    }

    isDeleting = true;
    lastOperationErrorMessage = null;
    _onStateChanged();

    final result = await _deleteDefinition(definition.id);
    var shouldReload = false;
    String? errorMessage;
    result.fold(
      (_) {
        selectedActionId = null;
        shouldReload = true;
      },
      (failure) {
        errorMessage = _messageFor(failure);
        lastOperationErrorMessage = errorMessage;
      },
    );

    isDeleting = false;
    if (!shouldReload) {
      _onStateChanged();
    }

    return (shouldReload: shouldReload, errorMessage: errorMessage);
  }

  Future<bool> saveCommandLineAction({
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
  }) => _saveHandlers.saveCommandLineAction(
    host: this,
    name: name,
    command: command,
    canSave: canSave,
    actionId: actionId,
    description: description,
    workingDirectory: workingDirectory,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
  );

  Future<bool> saveExecutableAction({
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
  }) => _saveHandlers.saveExecutableAction(
    host: this,
    name: name,
    executablePath: executablePath,
    arguments: arguments,
    canSave: canSave,
    actionId: actionId,
    description: description,
    workingDirectory: workingDirectory,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
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
  }) => _saveHandlers.saveScriptAction(
    host: this,
    name: name,
    scriptPath: scriptPath,
    arguments: arguments,
    canSave: canSave,
    actionId: actionId,
    description: description,
    interpreterPath: interpreterPath,
    workingDirectory: workingDirectory,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
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
  }) => _saveHandlers.saveJarAction(
    host: this,
    name: name,
    jarPath: jarPath,
    arguments: arguments,
    canSave: canSave,
    actionId: actionId,
    description: description,
    javaExecutablePath: javaExecutablePath,
    workingDirectory: workingDirectory,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
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
  }) => _saveHandlers.saveEmailAction(
    host: this,
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
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
  );

  Future<bool> saveComObjectAction({
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
  }) => _saveHandlers.saveComObjectAction(
    host: this,
    name: name,
    progId: progId,
    memberName: memberName,
    arguments: arguments,
    canSave: canSave,
    actionId: actionId,
    description: description,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
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
  }) => _saveHandlers.saveDeveloperData7Action(
    host: this,
    name: name,
    executorPath: executorPath,
    projectPath: projectPath,
    connectionId: connectionId,
    connectionLabel: connectionLabel,
    canSave: canSave,
    actionId: actionId,
    description: description,
    data7ConfigPath: data7ConfigPath,
    state: state,
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
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
  );

  Future<void> loadDeveloperData7Connections({
    required String actionId,
    required String data7ConfigPath,
    String? selectedConnectionId,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) async {
    final reloadGeneration = ++_developerConnectionReloadGeneration;
    var publishReloadState = true;
    isLoadingDeveloperConnections = true;
    developerConnectionLookupMessage = null;
    _onStateChanged();

    try {
      final result = await _listDeveloperData7Connections(
        DeveloperData7ConnectionLookupRequest(
          actionId: actionId.trim(),
          data7ConfigPath: AgentActionPathReference(originalPath: data7ConfigPath.trim()),
          pathPolicy: pathPolicy,
          selectedConnectionId: selectedConnectionId,
        ),
      );

      if (reloadGeneration != _developerConnectionReloadGeneration) {
        publishReloadState = false;
        return;
      }

      result.fold(
        (lookup) {
          developerConnections = lookup.connections;
          resolvedDeveloperData7ConfigPath = lookup.resolvedConfigPath.displayPath;
          usedDefaultDeveloperData7ConfigPath = lookup.usedDefaultLocation;
          developerConnectionLookupMessage = null;
        },
        (failure) {
          developerConnections = <DeveloperData7ConnectionOption>[];
          resolvedDeveloperData7ConfigPath = null;
          usedDefaultDeveloperData7ConfigPath = false;
          developerConnectionLookupMessage = _messageFor(failure);
        },
      );
    } on Object catch (error, stackTrace) {
      if (reloadGeneration != _developerConnectionReloadGeneration) {
        publishReloadState = false;
        return;
      }

      developerConnections = <DeveloperData7ConnectionOption>[];
      resolvedDeveloperData7ConfigPath = null;
      usedDefaultDeveloperData7ConfigPath = false;
      developerConnectionLookupMessage = _messageFor(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 connection lookup failed unexpectedly.',
          cause: error,
          context: {
            'action_id': actionId.trim(),
            'field': 'data7ConfigPath',
            'reason': 'developer_data7_connection_lookup_unexpected_error',
            'user_message': 'Nao foi possivel carregar as conexoes Data7. Tente novamente.',
            'stack_trace': stackTrace.toString(),
          },
        ),
      );
    } finally {
      if (publishReloadState) {
        isLoadingDeveloperConnections = false;
        invalidateCaches();
        _onStateChanged();
      }
    }
  }

  void clearDeveloperData7Connections({bool notify = true}) {
    developerConnections = <DeveloperData7ConnectionOption>[];
    developerConnectionLookupMessage = null;
    resolvedDeveloperData7ConfigPath = null;
    usedDefaultDeveloperData7ConfigPath = false;
    isLoadingDeveloperConnections = false;
    invalidateCaches();
    if (notify) {
      _onStateChanged();
    }
  }

  Future<String?> recordPreflightSuccess(AgentActionDefinition definition) async {
    final preflightSnapshotHash = preflightContentSnapshotHash(definition);
    final validatedAt = _now().toUtc();
    sessionPreflightSnapshotHashes[definition.id] = preflightSnapshotHash;
    sessionPreflightValidatedAt[definition.id] = validatedAt;

    final result = await _saveDefinition(
      definition.copyWith(
        lastPreflightSnapshotHash: preflightSnapshotHash,
        lastPreflightValidatedAt: validatedAt,
      ),
    );
    return result.fold(
      (savedDefinition) {
        definitions = definitions
            .map(
              (item) => item.id == savedDefinition.id ? savedDefinition : item,
            )
            .toList(growable: false);
        invalidateCaches();
        lastOperationErrorMessage = null;
        _onStateChanged();
        return null;
      },
      (failure) {
        final message = _messageFor(failure);
        lastOperationErrorMessage = message;
        _onStateChanged();
        return message;
      },
    );
  }

  void clearPreflightSessionForDefinition(String definitionId) {
    sessionPreflightSnapshotHashes.remove(definitionId);
    sessionPreflightValidatedAt.remove(definitionId);
  }

  String preflightContentSnapshotHash(AgentActionDefinition definition) {
    return _definitionSnapshotter.snapshotHash(
      definition.copyWith(state: AgentActionState.needsValidation),
    );
  }
}
