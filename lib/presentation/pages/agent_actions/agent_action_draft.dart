import 'dart:convert';
import 'dart:ui' show VoidCallback;

import 'package:flutter/widgets.dart' show ScrollController, TextEditingController;
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';

/// Owns every controller and scalar flag the agent-action editor used to
/// hold loose in its `State`. Moving them here lets the widget:
///
/// - dispose 38+ controllers with a single call (`draft.dispose()`),
/// - attach/detach the dirty listener over the whole bundle in one go,
/// - build the domain `*Policy` objects from a testable holder instead
///   of from the live State,
/// - eventually swap UI without touching the storage layout.
///
/// Sub-bundles split the surface by use case (identity, command-line,
/// executable, script, jar, email, com object, developer, execution
/// policy). The draft itself does not call `setState` — callers continue
/// to mutate fields inside their own `setState` blocks, preserving the
/// current rebuild semantics with zero behavioural change.
class AgentActionDraft {
  AgentActionDraft();

  // ---------------------------------------------------------------------------
  // Sub-bundles
  // ---------------------------------------------------------------------------

  final AgentActionDraftIdentity identity = AgentActionDraftIdentity();
  final AgentActionDraftCommandLine commandLine = AgentActionDraftCommandLine();
  final AgentActionDraftExecutable executable = AgentActionDraftExecutable();
  final AgentActionDraftScript script = AgentActionDraftScript();
  final AgentActionDraftJar jar = AgentActionDraftJar();
  final AgentActionDraftEmail email = AgentActionDraftEmail();
  final AgentActionDraftComObject comObject = AgentActionDraftComObject();
  final AgentActionDraftDeveloper developer = AgentActionDraftDeveloper();
  final AgentActionDraftExecutionPolicy executionPolicy = AgentActionDraftExecutionPolicy();
  final AgentActionDraftDisplayBindings displayBindings = AgentActionDraftDisplayBindings();

  /// Scroll controller for the dialog-style editor. Lives at the draft
  /// level because the scroll position belongs to the form, not to any
  /// single sub-bundle.
  final ScrollController dialogScrollController = ScrollController();

  // ---------------------------------------------------------------------------
  // Scalar flags / kind / state
  // ---------------------------------------------------------------------------

  String? editingActionId;
  AgentActionDraftKind draftKind = AgentActionDraftKind.commandLine;
  AgentActionType draftType = AgentActionType.commandLine;
  PowerShellDraftMode powerShellMode = PowerShellDraftMode.inline;
  PowerShellExecutable powerShellExecutable = PowerShellExecutable.windowsPowerShell;
  AgentActionState state = AgentActionState.needsValidation;

  bool isDraftModifiedSinceLoad = false;
  bool applyingLoadedDefinition = false;
  bool notifyOnSuccess = false;
  bool notifyOnFailure = false;
  bool notifyOnTimeout = false;
  int maxAttempts = 1;
  bool allowRemoteRetry = false;
  int maxRuntimeMinutes = 30;
  bool killMainProcessOnTimeout = true;
  AgentActionOnAppExitBehavior onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
  AgentActionProcessWindowMode processWindowMode = AgentActionProcessWindowMode.normal;
  AgentActionOutputEncodingMode stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  AgentActionOutputEncodingMode stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  bool captureStdout = true;
  bool captureStderr = true;
  bool redactBeforePersisting = true;
  AgentActionConcurrencyBehavior concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
  bool remoteEnabled = false;
  bool remoteAdHoc = false;
  bool remoteApprovalGranted = false;
  bool runElevated = false;
  AgentActionPathChangePolicy pathChangePolicy = AgentActionPathChangePolicy.failIfChanged;
  AgentActionContextInjectionMode contextInjectionMode = AgentActionContextInjectionMode.argument;
  String? validationMessage;
  String developerConnectionSearchQuery = '';

  // ---------------------------------------------------------------------------
  // Listener wiring
  // ---------------------------------------------------------------------------

  List<TextEditingController> get _userEditableControllers => <TextEditingController>[
    identity.name,
    identity.description,
    commandLine.command,
    commandLine.workingDirectory,
    executable.targetPath,
    executable.arguments,
    script.path,
    script.interpreterPath,
    jar.path,
    jar.javaExecutablePath,
    email.smtpProfileId,
    email.from,
    email.to,
    email.cc,
    email.bcc,
    email.subject,
    email.body,
    email.attachments,
    comObject.progId,
    comObject.memberName,
    comObject.arguments,
    developer.executorPath,
    developer.projectPath,
    developer.data7ConfigPath,
    developer.connectionId,
    developer.connectionLabel,
    executionPolicy.maxRuntimeMinutes,
    executionPolicy.allowedProfiles,
    executionPolicy.allowedEnvironmentVariableNames,
    executionPolicy.environmentVariables,
    executionPolicy.acceptedExitCodes,
    executionPolicy.runtimeParameterSchema,
    executionPolicy.maxConcurrent,
    executionPolicy.maxQueued,
    executionPolicy.allowedWorkingDirectories,
    executionPolicy.allowedContextDirectories,
  ];

  /// Iterates every controller (including the read-only display ones
  /// and the developer connection search) so `dispose()` is a single
  /// call instead of 38 lines of boilerplate.
  Iterable<TextEditingController> get _allControllers sync* {
    yield* _userEditableControllers;
    yield developer.connectionSearch;
    yield displayBindings.actionTypeDisplay;
    yield displayBindings.powerShellModeDisplay;
  }

  void attachChangeListeners(VoidCallback callback) {
    for (final controller in _userEditableControllers) {
      controller.addListener(callback);
    }
  }

  void detachChangeListeners(VoidCallback callback) {
    for (final controller in _userEditableControllers) {
      controller.removeListener(callback);
    }
  }

  void dispose() {
    for (final controller in _allControllers) {
      controller.dispose();
    }
    dialogScrollController.dispose();
  }

  // ---------------------------------------------------------------------------
  // Domain policy builders (moved out of the widget)
  // ---------------------------------------------------------------------------

  AgentActionRetryPolicy retryPolicy() {
    return AgentActionRetryPolicy(
      maxAttempts: maxAttempts,
      allowRemote: allowRemoteRetry,
    );
  }

  AgentActionTimeoutPolicy timeoutPolicy() {
    return AgentActionTimeoutPolicy(
      maxRuntime: Duration(minutes: maxRuntimeMinutes),
      killMainProcessOnTimeout: killMainProcessOnTimeout,
    );
  }

  AgentActionNotificationPolicy notificationPolicy() {
    return AgentActionNotificationPolicy(
      notifyOnSuccess: notifyOnSuccess,
      notifyOnFailure: notifyOnFailure,
      notifyOnTimeout: notifyOnTimeout,
    );
  }

  AgentActionEnvironmentPolicy environmentPolicy() {
    return AgentActionEnvironmentPolicy(
      allowedProfiles: AgentActionDraftParsers.commaSeparatedTokens(executionPolicy.allowedProfiles.text),
      allowedVariableNames: AgentActionDraftParsers.commaSeparatedTokens(
        executionPolicy.allowedEnvironmentVariableNames.text,
      ),
      variables: AgentActionDraftParsers.environmentVariables(executionPolicy.environmentVariables.text),
    );
  }

  AgentActionExitCodePolicy exitCodePolicy(Set<int> acceptedExitCodes) {
    return AgentActionExitCodePolicy(acceptedExitCodes: acceptedExitCodes);
  }

  AgentActionLifecyclePolicy lifecyclePolicy() {
    return AgentActionLifecyclePolicy(onAppExit: onAppExit);
  }

  AgentActionProcessPolicy processPolicy() {
    return AgentActionProcessPolicy(windowMode: processWindowMode);
  }

  AgentActionEncodingPolicy encodingPolicy() {
    return AgentActionEncodingPolicy(
      stdout: stdoutEncodingMode,
      stderr: stderrEncodingMode,
    );
  }

  AgentActionCapturePolicy capturePolicy() {
    return AgentActionCapturePolicy(
      captureStdout: captureStdout,
      captureStderr: captureStderr,
      redactBeforePersisting: redactBeforePersisting,
    );
  }

  AgentActionQueuePolicy queuePolicy() {
    return AgentActionQueuePolicy(
      maxConcurrent: AgentActionDraftParsers.positiveInt(executionPolicy.maxConcurrent.text) ?? 1,
      maxQueued: AgentActionDraftParsers.positiveInt(executionPolicy.maxQueued.text) ?? 100,
      concurrencyBehavior: concurrencyBehavior,
    );
  }

  AgentActionPathPolicy pathPolicy() {
    return AgentActionPathPolicy(
      allowedWorkingDirectories: AgentActionDraftParsers.commaSeparatedTokens(
        executionPolicy.allowedWorkingDirectories.text,
      ),
      allowedContextDirectories: AgentActionDraftParsers.commaSeparatedTokens(
        executionPolicy.allowedContextDirectories.text,
      ),
    );
  }

  AgentActionElevatedPolicy elevatedPolicy({required bool elevatedFeatureEnabled}) {
    if (!elevatedFeatureEnabled) {
      return const AgentActionElevatedPolicy();
    }
    return AgentActionElevatedPolicy(runElevated: runElevated);
  }

  /// Parses the runtime parameter schema if present and returns the
  /// resulting [AgentActionContextPolicy]. Throws [FormatException]
  /// when the schema text is not a valid JSON object — callers should
  /// catch and translate to a user-friendly message.
  AgentActionContextPolicy contextPolicy() {
    final schemaText = executionPolicy.runtimeParameterSchema.text.trim();
    if (schemaText.isEmpty) {
      return AgentActionContextPolicy(injectionMode: contextInjectionMode);
    }

    final decoded = jsonDecode(schemaText);
    if (decoded is! Map) {
      throw const FormatException('Runtime parameter schema must be a JSON object.');
    }

    return AgentActionContextPolicy(
      injectionMode: contextInjectionMode,
      runtimeParameterSchema: decoded.cast<String, Object?>(),
    );
  }

  /// Builds the remote policy honouring the provider feature flags. The
  /// previous definition (when available) preserves audit metadata
  /// (`approvedBy`, `approvalReason`, `riskFingerprint`,
  /// `requiresReapproval`).
  AgentActionRemotePolicy remotePolicy({
    required bool remoteAdHocFeatureEnabled,
    required String localApprover,
    AgentActionDefinition? previousDefinition,
  }) {
    if (!remoteEnabled) {
      return const AgentActionRemotePolicy();
    }

    final previous = previousDefinition?.policies.remote;
    final DateTime? approvedAt;
    if (!remoteApprovalGranted) {
      approvedAt = null;
    } else if (previous?.approvedAt == null || (previous?.requiresReapproval ?? false)) {
      approvedAt = DateTime.now().toUtc();
    } else {
      approvedAt = previous!.approvedAt;
    }

    return AgentActionRemotePolicy(
      isEnabled: true,
      allowAdHoc: remoteAdHocFeatureEnabled && remoteAdHoc,
      approvedBy: approvedAt == null ? null : (previous?.approvedBy ?? localApprover),
      approvedAt: approvedAt,
      approvalReason: previous?.approvalReason,
      riskFingerprint: previous?.riskFingerprint,
      requiresReapproval: !remoteApprovalGranted && (previous?.requiresReapproval ?? false),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers used by the editor / mapper
  // ---------------------------------------------------------------------------

  /// True when the running build profile is "production" *and* the
  /// current draft kind needs a path allowlist for safe execution.
  bool requiresProductionPathAllowlist() {
    return switch (draftType) {
      AgentActionType.commandLine || AgentActionType.executable || AgentActionType.script => true,
      _ => false,
    };
  }

  /// True when the current draft writes captured stdout/stderr to the
  /// agent storage. Mirrors the legacy `_draftCapturesProcessOutput`.
  bool capturesProcessOutput() {
    return switch (draftType) {
      AgentActionType.commandLine ||
      AgentActionType.executable ||
      AgentActionType.script ||
      AgentActionType.jar ||
      AgentActionType.developer => true,
      AgentActionType.email || AgentActionType.comObject => false,
    };
  }
}

/// Top-level identity fields shared across every draft kind.
class AgentActionDraftIdentity {
  final TextEditingController name = TextEditingController();
  final TextEditingController description = TextEditingController();
}

/// Command-line specific draft fields (also reused by the PowerShell
/// inline mode through `command`).
class AgentActionDraftCommandLine {
  final TextEditingController command = TextEditingController();
  final TextEditingController workingDirectory = TextEditingController();
}

/// Executable target draft fields.
class AgentActionDraftExecutable {
  final TextEditingController targetPath = TextEditingController();

  /// Structured arguments controller. Shared with `script`, `jar` and
  /// the PowerShell `script` mode (legacy `_executableArgumentsController`).
  final TextEditingController arguments = TextEditingController();
}

/// Script-based draft fields (path + interpreter override).
class AgentActionDraftScript {
  final TextEditingController path = TextEditingController();
  final TextEditingController interpreterPath = TextEditingController();
}

/// Jar action draft fields.
class AgentActionDraftJar {
  final TextEditingController path = TextEditingController();
  final TextEditingController javaExecutablePath = TextEditingController();
}

/// Email action draft fields. All controllers are user-editable.
class AgentActionDraftEmail {
  final TextEditingController smtpProfileId = TextEditingController();
  final TextEditingController from = TextEditingController();
  final TextEditingController to = TextEditingController();
  final TextEditingController cc = TextEditingController();
  final TextEditingController bcc = TextEditingController();
  final TextEditingController subject = TextEditingController();
  final TextEditingController body = TextEditingController();
  final TextEditingController attachments = TextEditingController();
}

/// COM object action draft fields. `arguments` defaults to `{}` so a
/// freshly-created COM action shows a valid JSON object placeholder.
class AgentActionDraftComObject {
  final TextEditingController progId = TextEditingController();
  final TextEditingController memberName = TextEditingController();
  final TextEditingController arguments = TextEditingController(text: '{}');
}

/// Developer (Data7) action draft fields.
class AgentActionDraftDeveloper {
  final TextEditingController executorPath = TextEditingController();
  final TextEditingController projectPath = TextEditingController();
  final TextEditingController data7ConfigPath = TextEditingController();
  final TextEditingController connectionId = TextEditingController();
  final TextEditingController connectionLabel = TextEditingController();

  /// Search field over the developer connection selector. Lives in
  /// the developer bundle but is **not** part of the user-editable
  /// "dirty" listener set: typing in it does not mark the draft as
  /// modified.
  final TextEditingController connectionSearch = TextEditingController();
}

/// Execution / runtime policy controllers. Holds the text fields that
/// feed `environmentPolicy`, `queuePolicy`, `pathPolicy`, etc.
class AgentActionDraftExecutionPolicy {
  final TextEditingController maxRuntimeMinutes = TextEditingController();
  final TextEditingController allowedProfiles = TextEditingController();
  final TextEditingController allowedEnvironmentVariableNames = TextEditingController();
  final TextEditingController environmentVariables = TextEditingController();
  final TextEditingController acceptedExitCodes = TextEditingController();
  final TextEditingController runtimeParameterSchema = TextEditingController();
  final TextEditingController maxConcurrent = TextEditingController(text: '1');
  final TextEditingController maxQueued = TextEditingController(text: '100');
  final TextEditingController allowedWorkingDirectories = TextEditingController();
  final TextEditingController allowedContextDirectories = TextEditingController();
}

/// Read-only display controllers that mirror the current draft kind /
/// PowerShell mode in `TextEditingController`-backed dropdowns when the
/// definition is being edited (and the kind/mode is locked).
class AgentActionDraftDisplayBindings {
  final TextEditingController actionTypeDisplay = TextEditingController();
  final TextEditingController powerShellModeDisplay = TextEditingController();
}
