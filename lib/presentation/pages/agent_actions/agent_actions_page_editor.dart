import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_approval_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_developer_hints.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_mapper.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_validation.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_draft_field_groups.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_file_picker.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

abstract final class AgentActionEditorKeys {
  static const ValueKey<String> actionTypeDropdown = ValueKey<String>('agent_action_editor_type_dropdown');
  static const ValueKey<String> powerShellModeDropdown = ValueKey<String>(
    'agent_action_editor_powershell_mode_dropdown',
  );
  static const ValueKey<String> powerShellExecutableDropdown = ValueKey<String>(
    'agent_action_editor_powershell_executable_dropdown',
  );
  static const ValueKey<String> remoteReapprovalInfoBar = ValueKey<String>('agent_actions_remote_reapproval_info_bar');
  static const ValueKey<String> developerConnectionMissingInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_missing_info_bar',
  );
  static const ValueKey<String> developerConnectionUnknownInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_unknown_info_bar',
  );
  static const ValueKey<String> developerConnectionChangedInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_changed_info_bar',
  );
}

class AgentActionEditor extends StatefulWidget {
  const AgentActionEditor({
    required this.provider,
    required this.l10n,
    this.definition,
    this.showChrome = true,
    this.onSaved,
    this.dirtyNotifier,
    super.key,
  });

  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;
  final bool showChrome;
  final VoidCallback? onSaved;

  /// Optional external notifier that mirrors the editor's unsaved-changes
  /// state. The dialog wrapper uses this to prompt before discarding the
  /// draft when the user closes/dismisses the dialog.
  final ValueNotifier<bool>? dirtyNotifier;

  @override
  State<AgentActionEditor> createState() => _AgentActionEditorState();
}

const List<AgentActionDraftKind> _editableDraftKinds = <AgentActionDraftKind>[
  AgentActionDraftKind.commandLine,
  AgentActionDraftKind.executable,
  AgentActionDraftKind.script,
  AgentActionDraftKind.jar,
  AgentActionDraftKind.email,
  AgentActionDraftKind.comObject,
  AgentActionDraftKind.developer,
  AgentActionDraftKind.powerShell,
];

class _AgentActionEditorState extends State<AgentActionEditor> {
  static const int _dialogSectionCount = 6;
  static const String _defaultDeveloperExecutorPath = r'C:\Data7\bin\Executor.exe';
  static const String _defaultDeveloperConfigBinPath = r'C:\Data7\bin\Data7.Config';
  static const String _defaultDeveloperConfigRootPath = r'C:\Data7\Data7.Config';

  /// Single holder for every draft controller and flag the editor used
  /// to keep as 38 loose fields. The widget keeps mutating `_draft.x`
  /// inside `setState` blocks so rebuild semantics stay identical;
  /// `dispose()` and the dirty-listener wiring collapse into a single
  /// call each.
  final AgentActionDraft _draft = AgentActionDraft();

  /// File picker adapter — kept as a field so tests can inject a fake
  /// without monkey-patching the global `FilePicker.platform`.
  final AgentActionFilePicker _filePicker = const AgentActionFilePicker();

  int _visibleDialogSectionCount = _dialogSectionCount;

  static const AgentOperationalProfileResolver _operationalProfileResolver = AgentOperationalProfileResolver();
  static const String _localRemoteApprover = AgentActionApprovalConstants.localUiApprover;

  @override
  void initState() {
    super.initState();
    _draft.attachChangeListeners(_onDraftChanged);
    _loadDefinition(widget.definition);
    _resetVisibleDialogSections();
  }

  @override
  void didUpdateWidget(AgentActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition?.id != widget.definition?.id || oldWidget.definition?.type != widget.definition?.type) {
      _loadDefinition(widget.definition);
      _resetVisibleDialogSections();
    }
    if (oldWidget.l10n != widget.l10n) {
      _syncReadOnlyDisplayControllers();
    }
  }

  @override
  void dispose() {
    _draft.detachChangeListeners(_onDraftChanged);
    _draft.dispose();
    super.dispose();
  }

  void _setValidationMessage(String message) {
    setState(() {
      _draft.validationMessage = message;
    });
  }

  void _onDraftChanged() {
    if (_draft.applyingLoadedDefinition) {
      return;
    }
    if (_draft.isDraftModifiedSinceLoad) {
      return;
    }

    setState(() {
      _draft.isDraftModifiedSinceLoad = true;
      if (_draft.state == AgentActionState.active) {
        _draft.state = AgentActionState.needsValidation;
      }
    });
    widget.dirtyNotifier?.value = true;
  }

  void _resetVisibleDialogSections() {
    if (widget.showChrome) {
      _visibleDialogSectionCount = _dialogSectionCount;
      return;
    }

    _visibleDialogSectionCount = 1;
    _scheduleNextDialogSection();
  }

  void _scheduleNextDialogSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.showChrome || _visibleDialogSectionCount >= _dialogSectionCount) {
        return;
      }
      setState(() {
        _visibleDialogSectionCount += 1;
      });
      _scheduleNextDialogSection();
    });
  }

  bool _isDialogSectionVisible(int sectionIndex) {
    return widget.showChrome || sectionIndex < _visibleDialogSectionCount;
  }

  Future<bool> _showValidationDialog(String message) async {
    if (!mounted) {
      return false;
    }

    await MessageModal.showWarning<void>(
      context: context,
      title: widget.l10n.agentActionsValidationTitle,
      message: message,
    );
    return false;
  }

  Future<bool> _showSaveFailureDialog() async {
    final message = widget.provider.errorMessage?.trim();
    if (message == null || message.isEmpty || !mounted) {
      return false;
    }

    await MessageModal.showError<void>(
      context: context,
      title: widget.l10n.agentActionsErrorTitle,
      message: message,
    );
    return false;
  }

  AgentActionType _actionTypeForDraftKind(AgentActionDraftKind draftKind) =>
      agentActionTypeForDraftKind(draftKind, _draft.powerShellMode);

  void _setDraftKind(AgentActionDraftKind draftKind) {
    _draft.draftKind = draftKind;
    if (draftKind == AgentActionDraftKind.powerShell && _isPowerShellModeUnavailable(_draft.powerShellMode)) {
      _draft.powerShellMode = _defaultAvailablePowerShellMode();
    }
    _draft.draftType = _actionTypeForDraftKind(draftKind);
    _syncReadOnlyDisplayControllers();
  }

  void _setPowerShellMode(PowerShellDraftMode mode) {
    _draft.powerShellMode = mode;
    _draft.draftType = _actionTypeForDraftKind(AgentActionDraftKind.powerShell);
    _syncReadOnlyDisplayControllers();
  }

  void _syncReadOnlyDisplayControllers() {
    _setControllerText(_draft.displayBindings.actionTypeDisplay, _draftKindLabel(_draft.draftKind));
    _setControllerText(_draft.displayBindings.powerShellModeDisplay, powerShellDraftModeLabel(_draft.powerShellMode, widget.l10n));
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    controller.text = text;
  }

  String _powerShellExecutableName(PowerShellExecutable executable) => powerShellExecutableName(executable);

  String _draftKindLabel(AgentActionDraftKind draftKind) => agentActionDraftKindLabel(draftKind, widget.l10n);

  bool _isDraftKindUnavailable(AgentActionDraftKind draftKind) {
    if (draftKind == AgentActionDraftKind.powerShell) {
      return PowerShellDraftMode.values.every(_isPowerShellModeUnavailable);
    }

    return widget.provider.isActionTypeUnavailable(_actionTypeForDraftKind(draftKind));
  }

  bool _isPowerShellModeUnavailable(PowerShellDraftMode mode) {
    return switch (mode) {
      PowerShellDraftMode.inline => widget.provider.isActionTypeUnavailable(AgentActionType.commandLine),
      PowerShellDraftMode.script => widget.provider.isActionTypeUnavailable(AgentActionType.script),
    };
  }

  PowerShellDraftMode _defaultAvailablePowerShellMode() {
    for (final mode in PowerShellDraftMode.values) {
      if (!_isPowerShellModeUnavailable(mode)) {
        return mode;
      }
    }

    return PowerShellDraftMode.inline;
  }

  /// Thin wrapper around [AgentActionDraftMapper.applyDefinition] that
  /// injects the live provider capabilities and the editor's
  /// `setState`-bound hooks.
  void _loadDefinition(AgentActionDefinition? definition) {
    const mapper = AgentActionDraftMapper();
    mapper.applyDefinition(
      _draft,
      definition,
      capabilities: _draftCapabilities(),
      hooks: _draftMapperHooks(),
    );
  }

  /// Thin wrapper around [AgentActionDraftMapper.clear].
  void _clearDraft([AgentActionDraftKind? draftKind]) {
    const mapper = AgentActionDraftMapper();
    mapper.clear(
      _draft,
      draftKind: draftKind,
      hooks: _draftMapperHooks(),
    );
  }

  AgentActionDraftCapabilities _draftCapabilities() {
    return AgentActionDraftCapabilities(
      remoteAdHocEnabled: widget.provider.isRemoteAdHocAgentActionsEnabled,
      elevatedEnabled: widget.provider.isElevatedAgentActionsEnabled,
    );
  }

  AgentActionDraftMapperHooks _draftMapperHooks() {
    return AgentActionDraftMapperHooks(
      clearDeveloperConnections: () => widget.provider.clearDeveloperData7Connections(notify: false),
      markDirty: (value) => widget.dirtyNotifier?.value = value,
      setDraftKind: _setDraftKind,
      scheduleDeveloperConnectionReload: _scheduleDeveloperConnectionReload,
    );
  }

  // Policy builders moved to `AgentActionDraft` (see Fase 1). Thin
  // wrappers below keep the call sites short and inject the provider
  // feature flags that the policy builders cannot infer on their own.

  AgentActionElevatedPolicy _draftElevatedPolicy() =>
      _draft.elevatedPolicy(elevatedFeatureEnabled: widget.provider.isElevatedAgentActionsEnabled);

  AgentActionRemotePolicy _draftRemotePolicy() => _draft.remotePolicy(
        remoteAdHocFeatureEnabled: widget.provider.isRemoteAdHocAgentActionsEnabled,
        localApprover: _localRemoteApprover,
        previousDefinition: widget.definition,
      );

  bool get _shouldShowProductionPathAllowlistWarning {
    if (!_operationalProfileResolver.isProductionProfile || !_draft.requiresProductionPathAllowlist()) {
      return false;
    }
    return _draft.pathPolicy().allowedWorkingDirectories.isEmpty;
  }

  /// Builds the identity row (name + type + state + preflight info
  /// bar) by feeding the live editor state into the extracted
  /// [AgentActionIdentitySection] / [AgentActionPreflightGateInfoBar].
  Widget _buildIdentitySection(bool saving) {
    final definition = widget.definition;
    final canSelectActiveState = widget.provider.canSetDefinitionActive(
      _draft.editingActionId,
      draftModified: _draft.isDraftModifiedSinceLoad,
    );
    final preflightInfoBar = AgentActionPreflightGateInfoBar(
      l10n: widget.l10n,
      state: AgentActionPreflightGateState(
        canSelectActiveState: canSelectActiveState,
        isDraftModifiedSinceLoad: _draft.isDraftModifiedSinceLoad,
        hasDefinition: definition != null,
        preflightExpiresAt:
            definition == null ? null : widget.provider.preflightExpiresAtForDefinition(definition),
        isPreflightExpired:
            definition != null && widget.provider.isPreflightExpiredForDefinition(definition),
      ),
    );

    return AgentActionIdentitySection(
      l10n: widget.l10n,
      enabled: !saving && widget.provider.canSaveAction,
      isEditing: _draft.editingActionId != null,
      actionTypeDisplayController: _draft.displayBindings.actionTypeDisplay,
      draftKind: _draft.draftKind,
      editableDraftKinds: _editableDraftKinds,
      isDraftKindUnavailable: _isDraftKindUnavailable,
      draftKindLabel: _draftKindLabel,
      onDraftKindChanged: (value) => setState(() => _clearDraft(value)),
      nameController: _draft.identity.name,
      state: _draft.state,
      canSelectActiveState: canSelectActiveState,
      stateLabelForValue: (state) => agentActionEditorStateLabel(state, widget.l10n),
      onStateChanged: (value) {
        if (value == AgentActionState.active && !canSelectActiveState) {
          _setValidationMessage(widget.l10n.agentActionsPreflightRequiredForActive);
          return;
        }
        setState(() {
          _draft.state = value;
          _draft.validationMessage = null;
        });
      },
      preflightInfoBar: preflightInfoBar,
      actionTypeDropdownKey: AgentActionEditorKeys.actionTypeDropdown,
    );
  }

  /// Pure validators (no `setState`, no `widget.provider`). The editor
  /// applies the resulting message through [_applyValidationFailure].
  /// Defaults to a fresh `ActionEnvironmentResolver`, which is
  /// stateless.
  static const AgentActionDraftValidators _validators = AgentActionDraftValidators();

  /// Runs the policy validators and copies the resulting message into
  /// the draft via `setState`. Returns `true` when every policy is
  /// valid. Replaces the previous trio of `_validateDraftXxx` methods
  /// that each set `_draft.validationMessage` as a side-effect.
  bool _validateDraftPolicies() {
    final result = _validators.validatePolicies(_draft, l10n: widget.l10n);
    return _applyValidationFailure(result);
  }

  bool _applyValidationFailure(DraftValidationResult result) {
    if (result is DraftValidationInvalid) {
      setState(() {
        _draft.validationMessage = result.message;
      });
      return false;
    }
    return true;
  }

  Set<int>? _tryParseAcceptedExitCodes(String input) => AgentActionDraftParsers.acceptedExitCodes(input);

  Future<bool> _save() async {
    final preSaveResult = _validators.validateBeforeSave(
      _draft,
      l10n: widget.l10n,
      canSetActive: widget.provider.canSetDefinitionActive(
        _draft.editingActionId,
        draftModified: _draft.isDraftModifiedSinceLoad,
      ),
    );
    if (preSaveResult is DraftValidationInvalid) {
      _setValidationMessage(preSaveResult.message);
      return _showValidationDialog(preSaveResult.message);
    }

    // The required-fields branch above already rejected an invalid
    // accepted-exit-codes payload, but we still need the parsed set
    // for the policy builders below.
    final acceptedExitCodes = _tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text);
    if (acceptedExitCodes == null) {
      final message = widget.l10n.agentActionsFormInvalidExitCodes;
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    final saveRequest = switch (_draft.draftKind) {
      AgentActionDraftKind.commandLine => _saveCommandLineDraft(),
      AgentActionDraftKind.executable => _saveExecutableDraft(),
      AgentActionDraftKind.script => _saveScriptDraft(),
      AgentActionDraftKind.jar => _saveJarDraft(),
      AgentActionDraftKind.email => _saveEmailDraft(),
      AgentActionDraftKind.comObject => _saveComObjectDraft(),
      AgentActionDraftKind.developer => _saveDeveloperDraft(),
      AgentActionDraftKind.powerShell => _savePowerShellDraft(),
    };
    final saveResult = await saveRequest;
    if (!saveResult) {
      final validationMessage = _draft.validationMessage;
      if (validationMessage != null && validationMessage.isNotEmpty) {
        return _showValidationDialog(validationMessage);
      }
      return _showSaveFailureDialog();
    }

    setState(() {
      _draft.validationMessage = null;
      _draft.isDraftModifiedSinceLoad = false;
    });
    widget.dirtyNotifier?.value = false;
    widget.onSaved?.call();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.provider.isSaving;
    final saveButton = Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: saving || !widget.provider.canSaveAction
            ? null
            : () {
                unawaited(_save());
              },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (saving)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.save),
            const SizedBox(width: AppSpacing.xs),
            Text(widget.l10n.agentActionsFormSave),
          ],
        ),
      ),
    );
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showChrome) ...[
          const Divider(),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _draft.editingActionId == null ? _createTitle() : _editTitle(),
                style: context.sectionTitle,
              ),
            ),
            if (widget.showChrome)
              Button(
                onPressed: saving
                    ? null
                    : () {
                        setState(_clearDraft);
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.add),
                    const SizedBox(width: AppSpacing.xs),
                    Text(widget.l10n.agentActionsFormNew),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isDialogSectionVisible(0)) _buildIdentitySection(saving),
        if (_isDialogSectionVisible(1)) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: widget.l10n.agentActionsFormDescription,
            controller: _draft.identity.description,
            enabled: !saving && widget.provider.canSaveAction,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._buildDraftFields(saving),
        ],
        if (_isDialogSectionVisible(2)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionExecutionPoliciesSection(
            l10n: widget.l10n,
            enabled: !saving && widget.provider.canSaveAction,
            elevatedFeatureEnabled: widget.provider.isElevatedAgentActionsEnabled,
            elevatedRunnerReady:
                widget.provider.isElevatedRunnerConfigured && !widget.provider.isElevatedRunnerDegraded,
            maxAttempts: _draft.maxAttempts,
            maxRuntimeMinutesController: _draft.executionPolicy.maxRuntimeMinutes,
            killMainProcessOnTimeout: _draft.killMainProcessOnTimeout,
            allowRemoteRetry: _draft.allowRemoteRetry,
            runElevated: _draft.runElevated,
            contextInjectionMode: _draft.contextInjectionMode,
            pathChangePolicy: _draft.pathChangePolicy,
            runtimeParameterSchemaController: _draft.executionPolicy.runtimeParameterSchema,
            callbacks: AgentActionExecutionPoliciesCallbacks(
              onMaxAttemptsChanged: (value) => setState(() => _draft.maxAttempts = value),
              onMaxRuntimeMinutesChanged: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed != null && parsed > 0) {
                  setState(() => _draft.maxRuntimeMinutes = parsed);
                }
              },
              onKillOnTimeoutChanged: (value) => setState(() => _draft.killMainProcessOnTimeout = value),
              onAllowRemoteRetryChanged: (value) => setState(() => _draft.allowRemoteRetry = value),
              onRunElevatedChanged: (value) => unawaited(_onRunElevatedChanged(value)),
              onContextInjectionModeChanged: (value) => setState(() => _draft.contextInjectionMode = value),
              onPathChangePolicyChanged: (value) => setState(() => _draft.pathChangePolicy = value),
            ),
          ),
        ],
        if (_isDialogSectionVisible(3)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionRuntimePoliciesSection(
            l10n: widget.l10n,
            enabled: !saving && widget.provider.canSaveAction,
            currentProfile: _operationalProfileResolver.currentProfile,
            allowedProfilesController: _draft.executionPolicy.allowedProfiles,
            allowedEnvironmentVariableNamesController: _draft.executionPolicy.allowedEnvironmentVariableNames,
            environmentVariablesController: _draft.executionPolicy.environmentVariables,
            maxConcurrentController: _draft.executionPolicy.maxConcurrent,
            maxQueuedController: _draft.executionPolicy.maxQueued,
            concurrencyBehavior: _draft.concurrencyBehavior,
            allowedWorkingDirectoriesController: _draft.executionPolicy.allowedWorkingDirectories,
            allowedContextDirectoriesController: _draft.executionPolicy.allowedContextDirectories,
            showProductionPathAllowlistWarning: _shouldShowProductionPathAllowlistWarning,
            capturesProcessOutput: _draft.capturesProcessOutput(),
            processWindowMode: _draft.processWindowMode,
            captureStdout: _draft.captureStdout,
            captureStderr: _draft.captureStderr,
            redactBeforePersisting: _draft.redactBeforePersisting,
            stdoutEncodingMode: _draft.stdoutEncodingMode,
            stderrEncodingMode: _draft.stderrEncodingMode,
            acceptedExitCodesController: _draft.executionPolicy.acceptedExitCodes,
            onAppExit: _draft.onAppExit,
            callbacks: AgentActionRuntimePoliciesCallbacks(
              onConcurrencyBehaviorChanged: (value) => setState(() => _draft.concurrencyBehavior = value),
              onProcessWindowModeChanged: (value) => setState(() => _draft.processWindowMode = value),
              onCaptureStdoutChanged: (value) => setState(() => _draft.captureStdout = value),
              onCaptureStderrChanged: (value) => setState(() => _draft.captureStderr = value),
              onRedactBeforePersistingChanged: (value) => setState(() => _draft.redactBeforePersisting = value),
              onStdoutEncodingModeChanged: (value) => setState(() => _draft.stdoutEncodingMode = value),
              onStderrEncodingModeChanged: (value) => setState(() => _draft.stderrEncodingMode = value),
              onOnAppExitChanged: (value) => setState(() => _draft.onAppExit = value),
            ),
          ),
        ],
        if (_isDialogSectionVisible(4)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionRemotePolicySection(
            l10n: widget.l10n,
            enabled: !saving && widget.provider.canSaveAction,
            remoteFeatureEnabled: widget.provider.isRemoteAgentActionsEnabled,
            remoteAdHocFeatureEnabled: widget.provider.isRemoteAdHocAgentActionsEnabled,
            remoteEnabled: _draft.remoteEnabled,
            remoteAdHoc: _draft.remoteAdHoc,
            remoteApprovalGranted: _draft.remoteApprovalGranted,
            requiresReapproval: widget.definition?.policies.remote.requiresReapproval ?? false,
            reapprovalInfoBarKey: AgentActionEditorKeys.remoteReapprovalInfoBar,
            onRemoteEnabledChanged: (value) => unawaited(_onRemoteEnabledChanged(value)),
            onRemoteAdHocChanged: (value) => unawaited(_onRemoteAdHocChanged(value)),
          ),
        ],
        if (_isDialogSectionVisible(5)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionNotificationPolicySection(
            l10n: widget.l10n,
            enabled: !saving && widget.provider.canSaveAction,
            notifyOnSuccess: _draft.notifyOnSuccess,
            notifyOnFailure: _draft.notifyOnFailure,
            notifyOnTimeout: _draft.notifyOnTimeout,
            onNotifyOnSuccessChanged: (value) => setState(() => _draft.notifyOnSuccess = value),
            onNotifyOnFailureChanged: (value) => setState(() => _draft.notifyOnFailure = value),
            onNotifyOnTimeoutChanged: (value) => setState(() => _draft.notifyOnTimeout = value),
          ),
        ],
        if (widget.showChrome) ...[
          const SizedBox(height: AppSpacing.md),
          saveButton,
        ],
      ],
    );

    if (widget.showChrome) {
      return form;
    }

    return Column(
      children: [
        Expanded(
          child: PrimaryScrollController.none(
            child: Scrollbar(
              controller: _draft.dialogScrollController,
              child: ListView(
                controller: _draft.dialogScrollController,
                primary: false,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                children: [
                  form,
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            top: AppSpacing.sm,
            right: AppSpacing.lg,
          ),
          child: saveButton,
        ),
      ],
    );
  }

  Future<void> _onRemoteEnabledChanged(bool enabled) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      final needsReapproval = widget.definition?.policies.remote.requiresReapproval ?? false;
      var confirmed = false;
      if (context.mounted) {
        confirmed = needsReapproval
            ? await confirmReapproveRemoteAgentAction(
                context: context,
                l10n: widget.l10n,
              )
            : await confirmEnableRemoteAgentAction(
                context: context,
                l10n: widget.l10n,
              );
      }
      if (!confirmed || !context.mounted) {
        return;
      }

      setState(() {
        _draft.remoteEnabled = true;
        _draft.remoteApprovalGranted = true;
      });
      return;
    }

    setState(() {
      _draft.remoteEnabled = false;
      _draft.remoteAdHoc = false;
      _draft.remoteApprovalGranted = false;
    });
  }

  Future<void> _onRemoteAdHocChanged(bool enabled) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      var confirmed = false;
      if (context.mounted) {
        confirmed = await confirmEnableRemoteAdHocAgentAction(
          context: context,
          l10n: widget.l10n,
        );
      }
      if (!confirmed || !context.mounted) {
        return;
      }
    }

    setState(() {
      _draft.remoteAdHoc = enabled;
    });
  }

  Future<void> _onRunElevatedChanged(bool enabled) async {
    if (!enabled) {
      setState(() {
        _draft.runElevated = false;
      });
      return;
    }

    if (!context.mounted) {
      return;
    }

    final confirmed = await confirmEnableElevatedAgentAction(
      context: context,
      l10n: widget.l10n,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    setState(() {
      _draft.runElevated = true;
    });
  }

  List<Widget> _buildDraftFields(bool saving) {
    if (_draft.draftKind == AgentActionDraftKind.powerShell) {
      return _buildPowerShellDraftFields(saving);
    }

    final enabled = !saving && widget.provider.canSaveAction;
    return switch (_draft.draftType) {
      AgentActionType.commandLine => <Widget>[
        AgentActionCommandLineFields(
          l10n: widget.l10n,
          enabled: enabled,
          commandController: _draft.commandLine.command,
          workingDirectoryController: _draft.commandLine.workingDirectory,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.executable => <Widget>[
        AgentActionExecutableFields(
          l10n: widget.l10n,
          enabled: enabled,
          executableTargetPathController: _draft.executable.targetPath,
          argumentsController: _draft.executable.arguments,
          workingDirectoryController: _draft.commandLine.workingDirectory,
          onPickExecutablePath: _pickExecutableTargetPath,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.comObject => <Widget>[
        AgentActionComObjectFields(
          l10n: widget.l10n,
          enabled: enabled,
          comProgIdController: _draft.comObject.progId,
          comMemberNameController: _draft.comObject.memberName,
          comArgumentsController: _draft.comObject.arguments,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.email => <Widget>[
        AgentActionEmailFields(
          l10n: widget.l10n,
          enabled: enabled,
          smtpProfileIdController: _draft.email.smtpProfileId,
          fromController: _draft.email.from,
          toController: _draft.email.to,
          ccController: _draft.email.cc,
          bccController: _draft.email.bcc,
          subjectController: _draft.email.subject,
          bodyController: _draft.email.body,
          attachmentsController: _draft.email.attachments,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.jar => <Widget>[
        AgentActionJarFields(
          l10n: widget.l10n,
          enabled: enabled,
          jarPathController: _draft.jar.path,
          javaExecutablePathController: _draft.jar.javaExecutablePath,
          argumentsController: _draft.executable.arguments,
          workingDirectoryController: _draft.commandLine.workingDirectory,
          onPickJarPath: _pickJarPath,
          onPickJavaExecutablePath: _pickJavaExecutablePath,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.script => <Widget>[
        AgentActionScriptFields(
          l10n: widget.l10n,
          enabled: enabled,
          scriptPathController: _draft.script.path,
          interpreterPathController: _draft.script.interpreterPath,
          argumentsController: _draft.executable.arguments,
          workingDirectoryController: _draft.commandLine.workingDirectory,
          onPickScriptPath: _pickScriptPath,
          onPickInterpreterPath: _pickScriptInterpreterPath,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.developer => <Widget>[
        AgentActionDeveloperFields(
          l10n: widget.l10n,
          enabled: enabled,
          isLoadingConnections: widget.provider.isLoadingDeveloperConnections,
          usedDefaultConfigPath: widget.provider.usedDefaultDeveloperData7ConfigPath,
          connectionLookupMessage: widget.provider.developerConnectionLookupMessage,
          hasConnections: widget.provider.developerConnections.isNotEmpty,
          filterHasNoMatches: _developerConnectionFilterHasNoMatches,
          connectionOptions: _developerConnectionsForSelector()
              .map((option) => (id: option.id, label: option.label))
              .toList(growable: false),
          executorPathController: _draft.developer.executorPath,
          projectPathController: _draft.developer.projectPath,
          data7ConfigPathController: _draft.developer.data7ConfigPath,
          connectionIdController: _draft.developer.connectionId,
          connectionLabelController: _draft.developer.connectionLabel,
          connectionSearchController: _draft.developer.connectionSearch,
          binaryPathHints: _buildDeveloperBinaryPathHints(),
          connectionStatus: _buildDeveloperConnectionStatus(),
          configPathHints: _buildDeveloperConfigPathHints(),
          resolvedConfigHints: _buildDeveloperResolvedConfigHints(),
          callbacks: AgentActionDeveloperFieldsCallbacks(
            onBinaryPathChanged: _handleDeveloperBinaryPathChanged,
            onPickExecutorPath: _pickDeveloperExecutorPath,
            onPickProjectPath: _pickDeveloperProjectPath,
            onApplyDefaultExecutorPath: _applyDefaultDeveloperExecutorPath,
            onReloadConnections: () => unawaited(_reloadDeveloperConnections(pathPolicy: _draft.pathPolicy())),
            onConfigPathChanged: _handleDeveloperConfigPathChanged,
            onPickConfigPath: _pickDeveloperData7ConfigPath,
            onApplyDefaultConfigBinPath: _applyDefaultDeveloperData7ConfigBinPath,
            onApplyDefaultConfigRootPath: _applyDefaultDeveloperData7ConfigRootPath,
            onConnectionIdChanged: _handleDeveloperConnectionIdChanged,
            onConnectionSearchChanged: (value) => setState(() => _draft.developerConnectionSearchQuery = value),
            onConnectionSelected: _applyDeveloperConnectionSelection,
            onSubmitted: () => unawaited(_save()),
          ),
        ),
      ],
    };
  }

  List<Widget> _buildPowerShellDraftFields(bool saving) {
    return <Widget>[
      AgentActionPowerShellDraftFields(
        l10n: widget.l10n,
        enabled: !saving && widget.provider.canSaveAction,
        modeDisplayEnabled: !saving,
        isEditing: _draft.editingActionId != null,
        mode: _draft.powerShellMode,
        executable: _draft.powerShellExecutable,
        isModeUnavailable: _isPowerShellModeUnavailable,
        modeDisplayController: _draft.displayBindings.powerShellModeDisplay,
        commandController: _draft.commandLine.command,
        scriptPathController: _draft.script.path,
        argumentsController: _draft.executable.arguments,
        workingDirectoryController: _draft.commandLine.workingDirectory,
        modeDropdownKey: AgentActionEditorKeys.powerShellModeDropdown,
        executableDropdownKey: AgentActionEditorKeys.powerShellExecutableDropdown,
        onModeChanged: (value) => setState(() => _setPowerShellMode(value)),
        onExecutableChanged: (value) => setState(() => _draft.powerShellExecutable = value),
        onPickScriptPath: _pickPowerShellScriptPath,
        onSubmitted: () => unawaited(_save()),
      ),
    ];
  }

  List<Widget> _developerHintWrap(List<AgentActionEditorDeveloperHintData> hints) {
    if (hints.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      AgentActionEditorDeveloperHintsWrap(hints: hints),
    ];
  }

  List<Widget> _buildDeveloperBinaryPathHints() {
    return _developerHintWrap(
      AgentActionDeveloperHints.binaryPathHints(
        executorPath: _draft.developer.executorPath.text.trim(),
        projectPath: _draft.developer.projectPath.text.trim(),
        defaultExecutorPath: _defaultDeveloperExecutorPath,
        l10n: widget.l10n,
      ),
    );
  }

  List<Widget> _buildDeveloperConfigPathHints() {
    return _developerHintWrap(
      AgentActionDeveloperHints.configPathHints(
        configPath: _draft.developer.data7ConfigPath.text.trim(),
        defaultConfigBinPath: _defaultDeveloperConfigBinPath,
        defaultConfigRootPath: _defaultDeveloperConfigRootPath,
        l10n: widget.l10n,
      ),
    );
  }

  List<Widget> _buildDeveloperResolvedConfigHints() {
    return _developerHintWrap(
      AgentActionDeveloperHints.resolvedConfigHints(
        resolvedConfigPath: widget.provider.resolvedDeveloperData7ConfigPath,
        typedConfigPath: _draft.developer.data7ConfigPath.text,
        l10n: widget.l10n,
      ),
    );
  }

  List<Widget> _buildDeveloperConnectionStatus() {
    final definition = widget.definition;
    if (definition == null || definition.config is! DeveloperActionConfig) {
      return const <Widget>[];
    }
    if (_draft.draftType != AgentActionType.developer) {
      return const <Widget>[];
    }
    if (widget.provider.isLoadingDeveloperConnections) {
      return const <Widget>[];
    }

    final config = definition.config as DeveloperActionConfig;
    final selectedConnectionId = _draft.developer.connectionId.text.trim();
    if (selectedConnectionId.isEmpty) {
      return const <Widget>[];
    }

    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == selectedConnectionId)
        .firstOrNull;

    final savedConnectionId = config.connectionId.trim();
    final isSavedConnectionMissing = selectedConnectionId == savedConnectionId;
    if (selectedOption == null && (isSavedConnectionMissing || widget.provider.developerConnections.isNotEmpty)) {
      return <Widget>[
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          key: isSavedConnectionMissing
              ? AgentActionEditorKeys.developerConnectionMissingInfoBar
              : AgentActionEditorKeys.developerConnectionUnknownInfoBar,
          title: Text(
            isSavedConnectionMissing
                ? widget.l10n.agentActionsFormConnectionMissingTitle
                : widget.l10n.agentActionsFormConnectionUnknownTitle,
          ),
          content: Text(
            isSavedConnectionMissing
                ? widget.l10n.agentActionsFormConnectionMissingMessage
                : widget.l10n.agentActionsFormConnectionUnknownMessage,
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ];
    }

    final savedSnapshotHash = config.connectionSnapshotHash?.trim();
    if (selectedOption != null &&
        savedSnapshotHash != null &&
        savedSnapshotHash.isNotEmpty &&
        savedSnapshotHash != selectedOption.snapshotHash) {
      return <Widget>[
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          key: AgentActionEditorKeys.developerConnectionChangedInfoBar,
          title: Text(widget.l10n.agentActionsFormConnectionChangedTitle),
          content: Text(widget.l10n.agentActionsFormConnectionChangedMessage),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ];
    }

    return const <Widget>[];
  }

  Future<bool> _saveExecutableDraft() async {
    final executablePath = _draft.executable.targetPath.text.trim();
    if (executablePath.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutablePath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveExecutableAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      executablePath: executablePath,
      arguments: _parseStructuredArguments(_draft.executable.arguments.text),
      workingDirectory: _draft.commandLine.workingDirectory.text,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      encodingPolicy: _draft.encodingPolicy(),
      capturePolicy: _draft.capturePolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  Future<bool> _saveJarDraft() async {
    final jarPath = _draft.jar.path.text.trim();
    if (jarPath.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormJarPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveJarAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      jarPath: jarPath,
      javaExecutablePath: _draft.jar.javaExecutablePath.text,
      arguments: _parseStructuredArguments(_draft.executable.arguments.text),
      workingDirectory: _draft.commandLine.workingDirectory.text,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      encodingPolicy: _draft.encodingPolicy(),
      capturePolicy: _draft.capturePolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  Future<bool> _saveEmailDraft() async {
    final smtpProfileId = _draft.email.smtpProfileId.text.trim();
    if (smtpProfileId.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormSmtpProfileId);
      });
      return false;
    }

    final from = _draft.email.from.text.trim();
    if (from.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailFrom);
      });
      return false;
    }

    final to = _parseStructuredArguments(_draft.email.to.text);
    if (to.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailTo);
      });
      return false;
    }

    final subject = _draft.email.subject.text.trim();
    if (subject.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailSubject);
      });
      return false;
    }

    final body = _draft.email.body.text.trim();
    if (body.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailBody);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    final attachmentPaths = _parseStructuredArguments(_draft.email.attachments.text)
        .map(
          (path) => AgentActionPathReference(
            originalPath: path,
            pathChangePolicy: _draft.pathChangePolicy,
          ),
        )
        .toList(growable: false);

    return widget.provider.saveEmailAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      cc: _parseStructuredArguments(_draft.email.cc.text),
      bcc: _parseStructuredArguments(_draft.email.bcc.text),
      subjectTemplate: subject,
      bodyTemplate: body,
      attachmentPaths: attachmentPaths,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  Future<bool> _saveComObjectDraft() async {
    final progId = _draft.comObject.progId.text.trim();
    if (progId.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComProgId);
      });
      return false;
    }

    final memberName = _draft.comObject.memberName.text.trim();
    if (memberName.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComMemberName);
      });
      return false;
    }

    final argumentsResult = _parseComObjectArguments(_draft.comObject.arguments.text);
    if (argumentsResult == null) {
      setState(() {
        _draft.validationMessage = widget.l10n.agentActionsFormInvalidComArguments;
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveComObjectAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      progId: progId,
      memberName: memberName,
      arguments: argumentsResult,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  Map<String, Object?>? _parseComObjectArguments(String raw) => AgentActionDraftParsers.comObjectArguments(raw);

  Future<bool> _saveScriptDraft() async {
    final scriptPath = _draft.script.path.text.trim();
    if (scriptPath.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormScriptPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveScriptAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      scriptPath: scriptPath,
      interpreterPath: _draft.script.interpreterPath.text,
      arguments: _parseStructuredArguments(_draft.executable.arguments.text),
      workingDirectory: _draft.commandLine.workingDirectory.text,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      encodingPolicy: _draft.encodingPolicy(),
      capturePolicy: _draft.capturePolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  List<String> _parseStructuredArguments(String raw) => AgentActionDraftParsers.structuredArguments(raw);

  Future<bool> _saveCommandLineDraft() async {
    final command = _draft.commandLine.command.text.trim();
    if (command.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormCommand);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveCommandLineAction(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      command: command,
      workingDirectory: _draft.commandLine.workingDirectory.text,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      encodingPolicy: _draft.encodingPolicy(),
      capturePolicy: _draft.capturePolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  Future<bool> _savePowerShellDraft() async {
    if (_isPowerShellModeUnavailable(_draft.powerShellMode)) {
      setState(() {
        _draft.validationMessage = widget.l10n.agentActionsFormPowerShellModeUnavailable;
      });
      return false;
    }

    switch (_draft.powerShellMode) {
      case PowerShellDraftMode.inline:
        final command = _draft.commandLine.command.text.trim();
        if (command.isEmpty) {
          setState(() {
            _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormPowerShellCommand);
          });
          return false;
        }

        if (!_validateDraftPolicies()) {
          return false;
        }

        return widget.provider.saveCommandLineAction(
          actionId: _draft.editingActionId,
          name: _draft.identity.name.text.trim(),
          description: _draft.identity.description.text,
          command: PowerShellCommandLine.wrapInlineCommand(
            command,
            executable: _powerShellExecutableName(_draft.powerShellExecutable),
          ),
          workingDirectory: _draft.commandLine.workingDirectory.text,
          state: _draft.state,
          notificationPolicy: _draft.notificationPolicy(),
          retryPolicy: _draft.retryPolicy(),
          timeoutPolicy: _draft.timeoutPolicy(),
          environmentPolicy: _draft.environmentPolicy(),
          exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
          processPolicy: _draft.processPolicy(),
          encodingPolicy: _draft.encodingPolicy(),
          capturePolicy: _draft.capturePolicy(),
          lifecyclePolicy: _draft.lifecyclePolicy(),
          remotePolicy: _draftRemotePolicy(),
          elevatedPolicy: _draftElevatedPolicy(),
          contextPolicy: _draft.contextPolicy(),
          pathChangePolicy: _draft.pathChangePolicy,
          queuePolicy: _draft.queuePolicy(),
          pathPolicy: _draft.pathPolicy(),
        );
      case PowerShellDraftMode.script:
        final scriptPath = _draft.script.path.text.trim();
        if (scriptPath.isEmpty) {
          setState(() {
            _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormPowerShellScriptPath);
          });
          return false;
        }
        if (!PowerShellCommandLine.isPowerShellScriptPath(scriptPath)) {
          setState(() {
            _draft.validationMessage = widget.l10n.agentActionsFormPowerShellScriptPathInvalid;
          });
          return false;
        }

        if (!_validateDraftPolicies()) {
          return false;
        }

        return widget.provider.saveScriptAction(
          actionId: _draft.editingActionId,
          name: _draft.identity.name.text.trim(),
          description: _draft.identity.description.text,
          scriptPath: scriptPath,
          interpreterPath: _draft.powerShellExecutable == PowerShellExecutable.powerShell7
              ? PowerShellCommandLine.powerShell7Executable
              : '',
          arguments: _parseStructuredArguments(_draft.executable.arguments.text),
          workingDirectory: _draft.commandLine.workingDirectory.text,
          state: _draft.state,
          notificationPolicy: _draft.notificationPolicy(),
          retryPolicy: _draft.retryPolicy(),
          timeoutPolicy: _draft.timeoutPolicy(),
          environmentPolicy: _draft.environmentPolicy(),
          exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
          processPolicy: _draft.processPolicy(),
          encodingPolicy: _draft.encodingPolicy(),
          capturePolicy: _draft.capturePolicy(),
          lifecyclePolicy: _draft.lifecyclePolicy(),
          remotePolicy: _draftRemotePolicy(),
          elevatedPolicy: _draftElevatedPolicy(),
          contextPolicy: _draft.contextPolicy(),
          pathChangePolicy: _draft.pathChangePolicy,
          queuePolicy: _draft.queuePolicy(),
          pathPolicy: _draft.pathPolicy(),
        );
    }
  }

  Future<bool> _saveDeveloperDraft() async {
    final executorPath = _draft.developer.executorPath.text.trim();
    if (executorPath.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutorPath);
      });
      return false;
    }

    final projectPath = _draft.developer.projectPath.text.trim();
    if (projectPath.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormProjectPath);
      });
      return false;
    }

    final connectionId = _draft.developer.connectionId.text.trim();
    if (connectionId.isEmpty) {
      setState(() {
        _draft.validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormConnectionId);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveDeveloperData7Action(
      actionId: _draft.editingActionId,
      name: _draft.identity.name.text.trim(),
      description: _draft.identity.description.text,
      executorPath: executorPath,
      projectPath: projectPath,
      data7ConfigPath: _draft.developer.data7ConfigPath.text,
      connectionId: connectionId,
      connectionLabel: _draft.developer.connectionLabel.text,
      state: _draft.state,
      notificationPolicy: _draft.notificationPolicy(),
      retryPolicy: _draft.retryPolicy(),
      timeoutPolicy: _draft.timeoutPolicy(),
      environmentPolicy: _draft.environmentPolicy(),
      exitCodePolicy: _draft.exitCodePolicy(_tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text)!),
      processPolicy: _draft.processPolicy(),
      encodingPolicy: _draft.encodingPolicy(),
      capturePolicy: _draft.capturePolicy(),
      lifecyclePolicy: _draft.lifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draft.contextPolicy(),
      pathChangePolicy: _draft.pathChangePolicy,
      queuePolicy: _draft.queuePolicy(),
      pathPolicy: _draft.pathPolicy(),
    );
  }

  String _createTitle() {
    return switch (_draft.draftKind) {
      AgentActionDraftKind.commandLine => widget.l10n.agentActionsFormCreateTitle,
      AgentActionDraftKind.executable => widget.l10n.agentActionsFormCreateExecutableTitle,
      AgentActionDraftKind.script => widget.l10n.agentActionsFormCreateScriptTitle,
      AgentActionDraftKind.jar => widget.l10n.agentActionsFormCreateJarTitle,
      AgentActionDraftKind.email => widget.l10n.agentActionsFormCreateEmailTitle,
      AgentActionDraftKind.comObject => widget.l10n.agentActionsFormCreateComObjectTitle,
      AgentActionDraftKind.developer => widget.l10n.agentActionsFormCreateDeveloperTitle,
      AgentActionDraftKind.powerShell => widget.l10n.agentActionsFormCreatePowerShellTitle,
    };
  }

  String _editTitle() {
    return switch (_draft.draftKind) {
      AgentActionDraftKind.commandLine => widget.l10n.agentActionsFormEditTitle,
      AgentActionDraftKind.executable => widget.l10n.agentActionsFormEditExecutableTitle,
      AgentActionDraftKind.script => widget.l10n.agentActionsFormEditScriptTitle,
      AgentActionDraftKind.jar => widget.l10n.agentActionsFormEditJarTitle,
      AgentActionDraftKind.email => widget.l10n.agentActionsFormEditEmailTitle,
      AgentActionDraftKind.comObject => widget.l10n.agentActionsFormEditComObjectTitle,
      AgentActionDraftKind.developer => widget.l10n.agentActionsFormEditDeveloperTitle,
      AgentActionDraftKind.powerShell => widget.l10n.agentActionsFormEditPowerShellTitle,
    };
  }

  void _scheduleDeveloperConnectionReload({
    required AgentActionPathPolicy pathPolicy,
    required String? selectedConnectionId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _draft.draftType != AgentActionType.developer) {
        return;
      }
      unawaited(
        _reloadDeveloperConnections(
          pathPolicy: pathPolicy,
          selectedConnectionId: selectedConnectionId,
        ),
      );
    });
  }

  Future<void> _reloadDeveloperConnections({
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String? selectedConnectionId,
  }) async {
    final actionId = (_draft.editingActionId?.trim().isNotEmpty ?? false) ? _draft.editingActionId!.trim() : 'developer-draft';
    await widget.provider.loadDeveloperData7Connections(
      actionId: actionId,
      data7ConfigPath: _draft.developer.data7ConfigPath.text,
      selectedConnectionId: selectedConnectionId ?? _draft.developer.connectionId.text,
      pathPolicy: pathPolicy,
    );

    if (!mounted) {
      return;
    }

    final resolvedPath = widget.provider.resolvedDeveloperData7ConfigPath;
    final typedConfigPath = _draft.developer.data7ConfigPath.text.trim();
    if (resolvedPath != null &&
        resolvedPath.isNotEmpty &&
        (typedConfigPath.isEmpty || widget.provider.usedDefaultDeveloperData7ConfigPath)) {
      _draft.developer.data7ConfigPath.text = resolvedPath;
    }

    final selectedId = selectedConnectionId ?? _draft.developer.connectionId.text.trim();
    final selectedOption = widget.provider.developerConnections.where((option) => option.id == selectedId).firstOrNull;
    if (selectedOption != null) {
      _applyDeveloperConnectionSelection(selectedOption.id);
      return;
    }

    if (selectedId.isEmpty && widget.provider.developerConnections.length == 1) {
      _applyDeveloperConnectionSelection(widget.provider.developerConnections.single.id);
    }
  }

  void _applyDeveloperConnectionSelection(String? connectionId) {
    if (connectionId == null || connectionId.trim().isEmpty) {
      return;
    }

    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == connectionId)
        .firstOrNull;
    if (selectedOption == null) {
      return;
    }

    setState(() {
      _draft.developer.connectionId.text = selectedOption.id;
      _draft.developer.connectionLabel.text = selectedOption.label;
    });
  }

  void _handleDeveloperConfigPathChanged(String _) {
    widget.provider.clearDeveloperData7Connections(notify: false);
    setState(() {
      _draft.developer.connectionLabel.clear();
      _draft.developerConnectionSearchQuery = '';
      _draft.developer.connectionSearch.clear();
      _draft.validationMessage = null;
    });
  }

  bool get _developerConnectionFilterHasNoMatches {
    final query = _draft.developerConnectionSearchQuery.trim();
    if (query.isEmpty || widget.provider.developerConnections.isEmpty) {
      return false;
    }

    final needle = query.toLowerCase();
    return !widget.provider.developerConnections.any(
      (option) => option.id.toLowerCase().contains(needle) || option.label.toLowerCase().contains(needle),
    );
  }

  List<DeveloperData7ConnectionOption> _developerConnectionsForSelector() {
    final all = widget.provider.developerConnections;
    final query = _draft.developerConnectionSearchQuery.trim().toLowerCase();
    final matched = query.isEmpty
        ? all
        : all
              .where(
                (option) => option.id.toLowerCase().contains(query) || option.label.toLowerCase().contains(query),
              )
              .toList(growable: false);

    final selectedId = _draft.developer.connectionId.text.trim();
    if (selectedId.isEmpty || matched.any((option) => option.id == selectedId)) {
      return matched;
    }

    final selected = all.where((option) => option.id == selectedId).firstOrNull;
    if (selected == null) {
      return matched;
    }

    return <DeveloperData7ConnectionOption>[selected, ...matched];
  }

  void _handleDeveloperBinaryPathChanged(String _) {
    setState(() {
      _draft.validationMessage = null;
    });
  }

  void _handleDeveloperConnectionIdChanged(String value) {
    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == value.trim())
        .firstOrNull;
    setState(() {
      _draft.developer.connectionLabel.text = selectedOption?.label ?? '';
    });
  }

  Future<void> _pickJarPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseJarPath,
        allowedExtensions: const ['jar'],
        apply: (path) => _draft.jar.path.text = path,
      );

  Future<void> _pickJavaExecutablePath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseJavaExecutablePath,
        allowedExtensions: const ['exe'],
        apply: (path) => _draft.jar.javaExecutablePath.text = path,
      );

  Future<void> _pickScriptPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseScriptPath,
        allowedExtensions: const ['ps1', 'bat', 'cmd', 'py'],
        apply: (path) => _draft.script.path.text = path,
      );

  Future<void> _pickPowerShellScriptPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowsePowerShellScriptPath,
        allowedExtensions: const ['ps1'],
        apply: (path) => _draft.script.path.text = path,
      );

  Future<void> _pickScriptInterpreterPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseInterpreterPath,
        allowedExtensions: const ['exe'],
        apply: (path) => _draft.script.interpreterPath.text = path,
      );

  Future<void> _pickExecutableTargetPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseExecutablePath,
        allowedExtensions: const ['exe', 'bat', 'cmd'],
        apply: (path) => _draft.executable.targetPath.text = path,
      );

  Future<void> _pickDeveloperExecutorPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseExecutorPath,
        allowedExtensions: const ['exe'],
        apply: (path) => _draft.developer.executorPath.text = path,
      );

  void _applyDefaultDeveloperExecutorPath() {
    setState(() {
      _draft.developer.executorPath.text = _defaultDeveloperExecutorPath;
      _draft.validationMessage = null;
    });
  }

  Future<void> _pickDeveloperProjectPath() => _pickAndApply(
        dialogTitle: widget.l10n.agentActionsFormBrowseProjectPath,
        allowedExtensions: const ['7proj'],
        apply: (path) => _draft.developer.projectPath.text = path,
      );

  Future<void> _pickDeveloperData7ConfigPath() async {
    await _pickAndApply(
      dialogTitle: widget.l10n.agentActionsFormBrowseData7ConfigPath,
      allowedExtensions: const ['config'],
      apply: (path) {
        _draft.developer.data7ConfigPath.text = path;
        _draft.developer.connectionId.clear();
        _draft.developer.connectionLabel.clear();
      },
      onAfter: () async {
        widget.provider.clearDeveloperData7Connections(notify: false);
        await _reloadDeveloperConnections(pathPolicy: _draft.pathPolicy());
      },
    );
  }

  Future<void> _applyDefaultDeveloperData7ConfigBinPath() async {
    await _applyDeveloperData7ConfigPath(_defaultDeveloperConfigBinPath);
  }

  Future<void> _applyDefaultDeveloperData7ConfigRootPath() async {
    await _applyDeveloperData7ConfigPath(_defaultDeveloperConfigRootPath);
  }

  Future<void> _applyDeveloperData7ConfigPath(String path) async {
    setState(() {
      _draft.developer.data7ConfigPath.text = path;
      _draft.developer.connectionId.clear();
      _draft.developer.connectionLabel.clear();
      _draft.validationMessage = null;
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await _reloadDeveloperConnections(
      pathPolicy: _draft.pathPolicy(),
    );
  }

  /// Single entry point used by every `_pickXxxPath` helper. Mirrors
  /// the previous 12 inlined methods that all wrapped
  /// `_pickSingleFile`, applied the result into a controller via
  /// `setState`, and translated platform failures into the standard
  /// validation message. The optional [onAfter] runs after `setState`
  /// completes — used by the developer config picker to reload the
  /// connection list.
  Future<void> _pickAndApply({
    required String dialogTitle,
    required List<String> allowedExtensions,
    required void Function(String selectedPath) apply,
    Future<void> Function()? onAfter,
  }) async {
    final String? selectedPath;
    try {
      selectedPath = await _filePicker.pickSingleFile(
        dialogTitle: dialogTitle,
        allowedExtensions: allowedExtensions,
      );
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _draft.validationMessage = widget.l10n.agentActionsFormBrowseFileError;
      });
      return;
    }
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      apply(selectedPath!);
      _draft.validationMessage = null;
    });

    if (onAfter != null) {
      await onAfter();
    }
  }
}

/// Defers mounting [AgentActionEditor] until after the first frame so dialog layout settles.
class DeferredAgentActionEditor extends StatefulWidget {
  const DeferredAgentActionEditor({
    required this.provider,
    required this.l10n,
    required this.onSaved,
    this.definition,
    this.dirtyNotifier,
    super.key,
  });

  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;
  final VoidCallback onSaved;
  final ValueNotifier<bool>? dirtyNotifier;

  @override
  State<DeferredAgentActionEditor> createState() => _DeferredAgentActionEditorState();
}

class _DeferredAgentActionEditorState extends State<DeferredAgentActionEditor> {
  bool _showEditor = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showEditor = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showEditor) {
      return const Center(child: ProgressRing());
    }

    return AgentActionEditor(
      provider: widget.provider,
      definition: widget.definition,
      l10n: widget.l10n,
      showChrome: false,
      onSaved: widget.onSaved,
      dirtyNotifier: widget.dirtyNotifier,
    );
  }
}
