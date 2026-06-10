import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_mapper.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_save_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_validation.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_developer_connection_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_draft_fields_builder.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_form_header.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_layout.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_path_pick_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_policy_confirmations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_policy_panel.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_save_button.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_titles.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_file_picker.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
  /// Single holder for every draft controller and flag the editor used
  /// to keep as 38 loose fields. The widget keeps mutating `_draft.x`
  /// inside `setState` blocks so rebuild semantics stay identical;
  /// `dispose()` and the dirty-listener wiring collapse into a single
  /// call each.
  final AgentActionDraft _draft = AgentActionDraft();

  /// File picker adapter — kept as a field so tests can inject a fake
  /// without monkey-patching the global `FilePicker.platform`.
  final AgentActionFilePicker _filePicker = const AgentActionFilePicker();

  int _visibleDialogSectionCount = AgentActionEditorLayout.dialogSectionCount;
  final Set<String> _shownDialogWarnings = <String>{};

  static const AgentOperationalProfileResolver _operationalProfileResolver = AgentOperationalProfileResolver();

  bool get _showInlineFeedback => widget.showChrome;

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
      _shownDialogWarnings.clear();
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
      _visibleDialogSectionCount = AgentActionEditorLayout.dialogSectionCount;
      return;
    }

    _visibleDialogSectionCount = 1;
    _scheduleNextDialogSection();
  }

  void _scheduleNextDialogSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.showChrome || _visibleDialogSectionCount >= AgentActionEditorLayout.dialogSectionCount) {
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

  void _publishDialogWarning(AgentActionEditorDialogWarning warning) {
    if (_showInlineFeedback || _shownDialogWarnings.contains(warning.key)) {
      return;
    }

    _shownDialogWarnings.add(warning.key);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await MessageModal.showWarning<void>(
        context: context,
        title: warning.title,
        message: warning.message,
      );
    });
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

  AgentActionPreflightGateState _preflightGateState() {
    final definition = widget.definition;
    return AgentActionPreflightGateState(
      canSelectActiveState: widget.provider.canSetDefinitionActive(
        _draft.editingActionId,
        draftModified: _draft.isDraftModifiedSinceLoad,
      ),
      isDraftModifiedSinceLoad: _draft.isDraftModifiedSinceLoad,
      hasDefinition: definition != null,
      preflightExpiresAt:
          definition == null ? null : widget.provider.preflightExpiresAtForDefinition(definition),
      isPreflightExpired:
          definition != null && widget.provider.isPreflightExpiredForDefinition(definition),
    );
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
      scheduleDeveloperConnectionReload: ({required pathPolicy, required selectedConnectionId}) {
        _developerConnectionCoordinator.scheduleReload(
          pathPolicy: pathPolicy,
          selectedConnectionId: selectedConnectionId,
          runAfterFrame: (Future<void> Function() reload) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _draft.draftType != AgentActionType.developer) {
                return;
              }
              unawaited(reload());
            });
          },
        );
      },
    );
  }

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
    final canSelectActiveState = _preflightGateState().canSelectActiveState;
    final preflightInfoBar = AgentActionPreflightGateInfoBar(
      l10n: widget.l10n,
      state: _preflightGateState(),
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
          final warning = AgentActionPreflightGateInfoBar.resolveWarning(
            _preflightGateState(),
            widget.l10n,
          );
          if (warning != null) {
            if (_showInlineFeedback) {
              _setValidationMessage(warning.message);
            } else {
              unawaited(
                MessageModal.showWarning<void>(
                  context: context,
                  title: warning.title,
                  message: warning.message,
                ),
              );
            }
          }
          return;
        }
        setState(() {
          _draft.state = value;
          _draft.validationMessage = null;
        });
      },
      preflightInfoBar: preflightInfoBar,
      actionTypeDropdownKey: AgentActionEditorKeys.actionTypeDropdown,
      showInlineFeedback: _showInlineFeedback,
    );
  }

  /// Pure validators (no `setState`, no `widget.provider`). Used for the
  /// pre-save checks in [_save]; the per-kind save mapping and policy
  /// validation now live in [AgentActionDraftSaveCoordinator].
  static const AgentActionDraftValidators _validators = AgentActionDraftValidators();

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
    // accepted-exit-codes payload, but we still need the parsed set
    // for the policy builders below.
    final acceptedExitCodes = _tryParseAcceptedExitCodes(_draft.executionPolicy.acceptedExitCodes.text);
    if (acceptedExitCodes == null) {
      final message = widget.l10n.agentActionsFormInvalidExitCodes;
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    final coordinator = AgentActionDraftSaveCoordinator(
      draft: _draft,
      provider: widget.provider,
      l10n: widget.l10n,
      previousDefinition: widget.definition,
    );
    final outcome = await coordinator.save(acceptedExitCodes: acceptedExitCodes);
    if (!mounted) {
      return false;
    }

    switch (outcome) {
      case AgentActionDraftSaveRejected(:final message):
        _setValidationMessage(message);
        return _showValidationDialog(message);
      case AgentActionDraftSaveForwarded(:final persisted):
        if (!persisted) {
          final validationMessage = _draft.validationMessage;
          if (validationMessage != null && validationMessage.isNotEmpty) {
            return _showValidationDialog(validationMessage);
          }
          return _showSaveFailureDialog();
        }
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
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) => _buildContent(context),
    );
  }

  AgentActionEditorDeveloperConnectionCoordinator get _developerConnectionCoordinator =>
      AgentActionEditorDeveloperConnectionCoordinator(
        draft: _draft,
        provider: widget.provider,
        definition: widget.definition,
        l10n: widget.l10n,
        showInlineFeedback: _showInlineFeedback,
        isMounted: () => mounted,
        onConnectionSelected: _applyDeveloperConnectionSelection,
        onDialogWarning: _publishDialogWarning,
      );

  AgentActionEditorPathPickCoordinator get _pathPickCoordinator => AgentActionEditorPathPickCoordinator(
        draft: _draft,
        l10n: widget.l10n,
        filePicker: _filePicker,
        isMounted: () => mounted,
        onValidationMessage: (message) {
          _setValidationMessage(message);
          if (!_showInlineFeedback) {
            _publishDialogWarning(
              AgentActionEditorDialogWarning(
                key: 'browse_file_error',
                title: widget.l10n.agentActionsValidationTitle,
                message: message,
              ),
            );
          }
        },
        onPathApplied: (void Function() applyPath) {
          setState(() {
            applyPath();
            _draft.validationMessage = null;
          });
        },
      );

  AgentActionEditorDraftFieldsBuilder get _draftFieldsBuilder => AgentActionEditorDraftFieldsBuilder(
        l10n: widget.l10n,
        provider: widget.provider,
        draft: _draft,
        definition: widget.definition,
        enabled: widget.provider.canSaveAction,
        filePicker: _filePicker,
        showInlineFeedback: _showInlineFeedback,
        onSave: () => unawaited(_save()),
        onValidationMessageChanged: (message) {
          setState(() {
            _draft.validationMessage = message;
          });
          final trimmed = message?.trim();
          if (!_showInlineFeedback && trimmed != null && trimmed.isNotEmpty) {
            _publishDialogWarning(
              AgentActionEditorDialogWarning(
                key: 'developer_validation',
                title: widget.l10n.agentActionsValidationTitle,
                message: trimmed,
              ),
            );
          }
        },
        onReloadConnections: _developerConnectionCoordinator.reloadDeveloperConnections,
        onDialogWarning: _showInlineFeedback ? null : _publishDialogWarning,
        onPickExecutableTargetPath: () => _pathPickCoordinator.pickExecutableTargetPath(),
        onPickJarPath: () => _pathPickCoordinator.pickJarPath(),
        onPickJavaExecutablePath: () => _pathPickCoordinator.pickJavaExecutablePath(),
        onPickScriptPath: () => _pathPickCoordinator.pickScriptPath(),
        onPickScriptInterpreterPath: () => _pathPickCoordinator.pickScriptInterpreterPath(),
        onPickPowerShellScriptPath: () => _pathPickCoordinator.pickPowerShellScriptPath(),
        isPowerShellModeUnavailable: _isPowerShellModeUnavailable,
        onPowerShellModeChanged: (value) => setState(() => _setPowerShellMode(value)),
        onPowerShellExecutableChanged: (value) => setState(() => _draft.powerShellExecutable = value),
      );

  Widget _buildContent(BuildContext context) {
    final saving = widget.provider.isSaving;
    final fieldsEnabled = !saving && widget.provider.canSaveAction;
    final saveButton = AgentActionEditorSaveButton(
      l10n: widget.l10n,
      saving: saving,
      enabled: !saving && widget.provider.canSaveAction,
      onPressed: () => unawaited(_save()),
    );
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgentActionEditorFormHeader(
          l10n: widget.l10n,
          title: _draft.editingActionId == null
              ? AgentActionEditorTitles.createTitle(_draft.draftKind, widget.l10n)
              : AgentActionEditorTitles.editTitle(_draft.draftKind, widget.l10n),
          showChrome: widget.showChrome,
          saving: saving,
          canSaveAction: widget.provider.canSaveAction,
          validationMessage: _draft.validationMessage,
          onClearValidation: () {
            setState(() {
              _draft.validationMessage = null;
            });
          },
          onNewDraft: () => setState(_clearDraft),
        ),
        if (_isDialogSectionVisible(0)) _buildIdentitySection(saving),
        if (_isDialogSectionVisible(1)) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: widget.l10n.agentActionsFormDescription,
            controller: _draft.identity.description,
            enabled: fieldsEnabled,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._draftFieldsBuilder.build(saving),
        ],
        AgentActionEditorPolicyPanel(
          l10n: widget.l10n,
          provider: widget.provider,
          definition: widget.definition,
          draft: _draft,
          enabled: fieldsEnabled,
          showProductionPathAllowlistWarning: _shouldShowProductionPathAllowlistWarning,
          visibleSections: _isDialogSectionVisible,
          executionCallbacks: AgentActionExecutionPoliciesCallbacks(
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
          runtimeCallbacks: AgentActionRuntimePoliciesCallbacks(
            onConcurrencyBehaviorChanged: (value) => setState(() => _draft.concurrencyBehavior = value),
            onProcessWindowModeChanged: (value) => setState(() => _draft.processWindowMode = value),
            onCaptureStdoutChanged: (value) => setState(() => _draft.captureStdout = value),
            onCaptureStderrChanged: (value) => setState(() => _draft.captureStderr = value),
            onRedactBeforePersistingChanged: (value) => setState(() => _draft.redactBeforePersisting = value),
            onStdoutEncodingModeChanged: (value) => setState(() => _draft.stdoutEncodingMode = value),
            onStderrEncodingModeChanged: (value) => setState(() => _draft.stderrEncodingMode = value),
            onOnAppExitChanged: (value) => setState(() => _draft.onAppExit = value),
          ),
          onRemoteEnabledChanged: (value) => unawaited(_onRemoteEnabledChanged(value)),
          onRemoteAdHocChanged: (value) => unawaited(_onRemoteAdHocChanged(value)),
          onNotifyOnSuccessChanged: (value) => setState(() => _draft.notifyOnSuccess = value),
          onNotifyOnFailureChanged: (value) => setState(() => _draft.notifyOnFailure = value),
          onNotifyOnTimeoutChanged: (value) => setState(() => _draft.notifyOnTimeout = value),
        ),
        if (widget.showChrome) ...[
          const SizedBox(height: AppSpacing.md),
          saveButton,
        ],
      ],
    );

    return AgentActionEditorLayout.build(
      showChrome: widget.showChrome,
      scrollController: _draft.dialogScrollController,
      form: form,
      saveButton: saveButton,
    );
  }

  Future<void> _onRemoteEnabledChanged(bool enabled) => AgentActionEditorPolicyConfirmations.handleRemoteEnabledChanged(
        context: context,
        l10n: widget.l10n,
        definition: widget.definition,
        enabled: enabled,
        onEnable: () => setState(() {
          _draft.remoteEnabled = true;
          _draft.remoteApprovalGranted = true;
        }),
        onDisable: () => setState(() {
          _draft.remoteEnabled = false;
          _draft.remoteAdHoc = false;
          _draft.remoteApprovalGranted = false;
        }),
      );

  Future<void> _onRemoteAdHocChanged(bool enabled) => AgentActionEditorPolicyConfirmations.handleRemoteAdHocChanged(
        context: context,
        l10n: widget.l10n,
        enabled: enabled,
        onApply: () => setState(() => _draft.remoteAdHoc = enabled),
      );

  Future<void> _onRunElevatedChanged(bool enabled) => AgentActionEditorPolicyConfirmations.handleRunElevatedChanged(
        context: context,
        l10n: widget.l10n,
        enabled: enabled,
        onEnable: () => setState(() => _draft.runElevated = true),
        onDisable: () => setState(() => _draft.runElevated = false),
      );

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

}
