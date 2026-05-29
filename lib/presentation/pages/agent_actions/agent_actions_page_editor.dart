import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_approval_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_developer_hints.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_draft_field_groups.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
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

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _workingDirectoryController = TextEditingController();
  final TextEditingController _executableTargetPathController = TextEditingController();
  final TextEditingController _executableArgumentsController = TextEditingController();
  final TextEditingController _scriptPathController = TextEditingController();
  final TextEditingController _scriptInterpreterPathController = TextEditingController();
  final TextEditingController _jarPathController = TextEditingController();
  final TextEditingController _javaExecutablePathController = TextEditingController();
  final TextEditingController _smtpProfileIdController = TextEditingController();
  final TextEditingController _emailFromController = TextEditingController();
  final TextEditingController _emailToController = TextEditingController();
  final TextEditingController _emailCcController = TextEditingController();
  final TextEditingController _emailBccController = TextEditingController();
  final TextEditingController _emailSubjectController = TextEditingController();
  final TextEditingController _emailBodyController = TextEditingController();
  final TextEditingController _emailAttachmentsController = TextEditingController();
  final TextEditingController _comProgIdController = TextEditingController();
  final TextEditingController _comMemberNameController = TextEditingController();
  final TextEditingController _comArgumentsController = TextEditingController(text: '{}');
  final TextEditingController _executorPathController = TextEditingController();
  final TextEditingController _projectPathController = TextEditingController();
  final TextEditingController _data7ConfigPathController = TextEditingController();
  final TextEditingController _connectionIdController = TextEditingController();
  final TextEditingController _connectionLabelController = TextEditingController();
  final TextEditingController _developerConnectionSearchController = TextEditingController();
  String _developerConnectionSearchQuery = '';
  final TextEditingController _maxRuntimeMinutesController = TextEditingController();
  final TextEditingController _allowedProfilesController = TextEditingController();
  final TextEditingController _allowedEnvironmentVariableNamesController = TextEditingController();
  final TextEditingController _environmentVariablesController = TextEditingController();
  final TextEditingController _acceptedExitCodesController = TextEditingController();
  final TextEditingController _runtimeParameterSchemaController = TextEditingController();
  final TextEditingController _maxConcurrentController = TextEditingController(text: '1');
  final TextEditingController _maxQueuedController = TextEditingController(text: '100');
  final TextEditingController _allowedWorkingDirectoriesController = TextEditingController();
  final TextEditingController _allowedContextDirectoriesController = TextEditingController();
  final TextEditingController _actionTypeDisplayController = TextEditingController();
  final TextEditingController _powerShellModeDisplayController = TextEditingController();
  final ScrollController _dialogScrollController = ScrollController();

  String? _editingActionId;
  AgentActionDraftKind _draftKind = AgentActionDraftKind.commandLine;
  AgentActionType _draftType = AgentActionType.commandLine;
  PowerShellDraftMode _powerShellMode = PowerShellDraftMode.inline;
  PowerShellExecutable _powerShellExecutable = PowerShellExecutable.windowsPowerShell;
  AgentActionState _state = AgentActionState.needsValidation;
  bool _isDraftModifiedSinceLoad = false;
  bool _applyingLoadedDefinition = false;
  bool _notifyOnSuccess = false;
  bool _notifyOnFailure = false;
  bool _notifyOnTimeout = false;
  int _maxAttempts = 1;
  bool _allowRemoteRetry = false;
  int _maxRuntimeMinutes = 30;
  bool _killMainProcessOnTimeout = true;
  AgentActionOnAppExitBehavior _onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
  AgentActionProcessWindowMode _processWindowMode = AgentActionProcessWindowMode.normal;
  AgentActionOutputEncodingMode _stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  AgentActionOutputEncodingMode _stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
  bool _captureStdout = true;
  bool _captureStderr = true;
  bool _redactBeforePersisting = true;
  AgentActionConcurrencyBehavior _concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
  bool _remoteEnabled = false;
  bool _remoteAdHoc = false;
  bool _remoteApprovalGranted = false;
  bool _runElevated = false;
  AgentActionPathChangePolicy _pathChangePolicy = AgentActionPathChangePolicy.failIfChanged;
  AgentActionContextInjectionMode _contextInjectionMode = AgentActionContextInjectionMode.argument;
  String? _validationMessage;
  int _visibleDialogSectionCount = _dialogSectionCount;

  static const AgentOperationalProfileResolver _operationalProfileResolver = AgentOperationalProfileResolver();
  static const ActionEnvironmentResolver _environmentResolver = ActionEnvironmentResolver();
  static const String _localRemoteApprover = AgentActionApprovalConstants.localUiApprover;

  @override
  void initState() {
    super.initState();
    _attachDraftChangeListeners();
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
    _detachDraftChangeListeners();
    _nameController.dispose();
    _descriptionController.dispose();
    _commandController.dispose();
    _workingDirectoryController.dispose();
    _executableTargetPathController.dispose();
    _executableArgumentsController.dispose();
    _scriptPathController.dispose();
    _scriptInterpreterPathController.dispose();
    _jarPathController.dispose();
    _javaExecutablePathController.dispose();
    _smtpProfileIdController.dispose();
    _emailFromController.dispose();
    _emailToController.dispose();
    _emailCcController.dispose();
    _emailBccController.dispose();
    _emailSubjectController.dispose();
    _emailBodyController.dispose();
    _emailAttachmentsController.dispose();
    _comProgIdController.dispose();
    _comMemberNameController.dispose();
    _comArgumentsController.dispose();
    _executorPathController.dispose();
    _projectPathController.dispose();
    _data7ConfigPathController.dispose();
    _connectionIdController.dispose();
    _connectionLabelController.dispose();
    _developerConnectionSearchController.dispose();
    _maxRuntimeMinutesController.dispose();
    _allowedProfilesController.dispose();
    _allowedEnvironmentVariableNamesController.dispose();
    _environmentVariablesController.dispose();
    _acceptedExitCodesController.dispose();
    _runtimeParameterSchemaController.dispose();
    _maxConcurrentController.dispose();
    _maxQueuedController.dispose();
    _allowedWorkingDirectoriesController.dispose();
    _allowedContextDirectoriesController.dispose();
    _actionTypeDisplayController.dispose();
    _powerShellModeDisplayController.dispose();
    _dialogScrollController.dispose();
    super.dispose();
  }

  void _setValidationMessage(String message) {
    setState(() {
      _validationMessage = message;
    });
  }

  List<TextEditingController> get _draftChangeControllers => <TextEditingController>[
    _nameController,
    _descriptionController,
    _commandController,
    _workingDirectoryController,
    _executableTargetPathController,
    _executableArgumentsController,
    _scriptPathController,
    _scriptInterpreterPathController,
    _jarPathController,
    _javaExecutablePathController,
    _smtpProfileIdController,
    _emailFromController,
    _emailToController,
    _emailCcController,
    _emailBccController,
    _emailSubjectController,
    _emailBodyController,
    _emailAttachmentsController,
    _comProgIdController,
    _comMemberNameController,
    _comArgumentsController,
    _executorPathController,
    _projectPathController,
    _data7ConfigPathController,
    _connectionIdController,
    _connectionLabelController,
    _maxRuntimeMinutesController,
    _allowedProfilesController,
    _allowedEnvironmentVariableNamesController,
    _environmentVariablesController,
    _acceptedExitCodesController,
    _runtimeParameterSchemaController,
    _maxConcurrentController,
    _maxQueuedController,
    _allowedWorkingDirectoriesController,
    _allowedContextDirectoriesController,
  ];

  void _attachDraftChangeListeners() {
    for (final controller in _draftChangeControllers) {
      controller.addListener(_onDraftChanged);
    }
  }

  void _detachDraftChangeListeners() {
    for (final controller in _draftChangeControllers) {
      controller.removeListener(_onDraftChanged);
    }
  }

  void _onDraftChanged() {
    if (_applyingLoadedDefinition) {
      return;
    }
    if (_isDraftModifiedSinceLoad) {
      return;
    }

    setState(() {
      _isDraftModifiedSinceLoad = true;
      if (_state == AgentActionState.active) {
        _state = AgentActionState.needsValidation;
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
      agentActionTypeForDraftKind(draftKind, _powerShellMode);

  void _setDraftKind(AgentActionDraftKind draftKind) {
    _draftKind = draftKind;
    if (draftKind == AgentActionDraftKind.powerShell && _isPowerShellModeUnavailable(_powerShellMode)) {
      _powerShellMode = _defaultAvailablePowerShellMode();
    }
    _draftType = _actionTypeForDraftKind(draftKind);
    _syncReadOnlyDisplayControllers();
  }

  void _setPowerShellMode(PowerShellDraftMode mode) {
    _powerShellMode = mode;
    _draftType = _actionTypeForDraftKind(AgentActionDraftKind.powerShell);
    _syncReadOnlyDisplayControllers();
  }

  void _syncReadOnlyDisplayControllers() {
    _setControllerText(_actionTypeDisplayController, _draftKindLabel(_draftKind));
    _setControllerText(_powerShellModeDisplayController, powerShellDraftModeLabel(_powerShellMode, widget.l10n));
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

  void _loadDefinition(AgentActionDefinition? definition) {
    _validationMessage = null;
    _isDraftModifiedSinceLoad = false;
    widget.dirtyNotifier?.value = false;
    _applyingLoadedDefinition = true;
    try {
      if (definition == null) {
        _clearDraft();
        return;
      }
      _editingActionId = definition.id;
      _nameController.text = definition.name;
      _descriptionController.text = definition.description ?? '';
      _state = definition.state;
      final notification = definition.policies.notification;
      _notifyOnSuccess = notification.notifyOnSuccess;
      _notifyOnFailure = notification.notifyOnFailure;
      _notifyOnTimeout = notification.notifyOnTimeout;
      final retry = definition.policies.retry;
      _maxAttempts = retry.maxAttempts < 1 ? 1 : retry.maxAttempts;
      _allowRemoteRetry = retry.allowRemote;
      final timeout = definition.policies.timeout;
      _maxRuntimeMinutes = timeout.maxRuntime.inMinutes < 1 ? 1 : timeout.maxRuntime.inMinutes;
      _maxRuntimeMinutesController.text = '$_maxRuntimeMinutes';
      _killMainProcessOnTimeout = timeout.killMainProcessOnTimeout;
      final environment = definition.policies.environment;
      _allowedProfilesController.text = environment.allowedProfiles.join(', ');
      _allowedEnvironmentVariableNamesController.text = environment.allowedVariableNames.join(', ');
      _environmentVariablesController.text = _formatEnvironmentVariables(environment.variables);
      final exitCode = definition.policies.exitCode;
      _acceptedExitCodesController.text = exitCode.acceptedExitCodes.join(', ');
      _onAppExit = definition.policies.lifecycle.onAppExit;
      _processWindowMode = definition.policies.process.windowMode;
      final encoding = definition.policies.encoding;
      _stdoutEncodingMode = encoding.stdout;
      _stderrEncodingMode = encoding.stderr;
      final capture = definition.policies.capture;
      _captureStdout = capture.captureStdout;
      _captureStderr = capture.captureStderr;
      _redactBeforePersisting = capture.redactBeforePersisting;
      final queue = definition.policies.queue;
      _maxConcurrentController.text = '${queue.maxConcurrent}';
      _maxQueuedController.text = '${queue.maxQueued}';
      _concurrencyBehavior = queue.concurrencyBehavior;
      final pathPolicy = definition.policies.path;
      _allowedWorkingDirectoriesController.text = pathPolicy.allowedWorkingDirectories.join(', ');
      _allowedContextDirectoriesController.text = pathPolicy.allowedContextDirectories.join(', ');
      final remote = definition.policies.remote;
      _remoteEnabled = remote.isEnabled;
      _remoteAdHoc = remote.allowAdHoc && widget.provider.isRemoteAdHocAgentActionsEnabled;
      _remoteApprovalGranted = remote.approvedAt != null && !remote.requiresReapproval;
      _runElevated = definition.policies.elevated.runElevated && widget.provider.isElevatedAgentActionsEnabled;
      final contextPolicy = definition.policies.context;
      _contextInjectionMode = contextPolicy.injectionMode;
      final runtimeSchema = contextPolicy.runtimeParameterSchema;
      _runtimeParameterSchemaController.text = runtimeSchema == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(runtimeSchema);
      switch (definition.config) {
        case final CommandLineActionConfig config:
          final powerShellCommand = PowerShellCommandLine.tryParseInlineCommand(config.command);
          if (powerShellCommand == null) {
            _setDraftKind(AgentActionDraftKind.commandLine);
            _commandController.text = config.command;
          } else {
            _powerShellMode = PowerShellDraftMode.inline;
            _powerShellExecutable = PowerShellCommandLine.isPowerShell7Executable(powerShellCommand.executable)
                ? PowerShellExecutable.powerShell7
                : PowerShellExecutable.windowsPowerShell;
            _setDraftKind(AgentActionDraftKind.powerShell);
            _commandController.text = powerShellCommand.command;
          }
          _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
          _pathChangePolicy = config.workingDirectory?.pathChangePolicy ?? AgentActionPathChangePolicy.failIfChanged;
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.clear();
          _comMemberNameController.clear();
          _comArgumentsController.text = '{}';
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final ExecutableActionConfig config:
          _setDraftKind(AgentActionDraftKind.executable);
          _commandController.clear();
          _executableTargetPathController.text = config.executablePath.originalPath;
          _executableArgumentsController.text = config.arguments.join('\n');
          _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.clear();
          _comMemberNameController.clear();
          _comArgumentsController.text = '{}';
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final ScriptActionConfig config:
          if (PowerShellCommandLine.isPowerShellScriptPath(config.scriptPath.originalPath)) {
            _powerShellMode = PowerShellDraftMode.script;
            _powerShellExecutable = PowerShellCommandLine.isPowerShell7Executable(config.interpreterPath?.originalPath)
                ? PowerShellExecutable.powerShell7
                : PowerShellExecutable.windowsPowerShell;
            _setDraftKind(AgentActionDraftKind.powerShell);
          } else {
            _setDraftKind(AgentActionDraftKind.script);
          }
          _commandController.clear();
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.text = config.scriptPath.originalPath;
          _scriptInterpreterPathController.text = config.interpreterPath?.originalPath ?? '';
          _executableArgumentsController.text = config.arguments.join('\n');
          _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.clear();
          _comMemberNameController.clear();
          _comArgumentsController.text = '{}';
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final JarActionConfig config:
          _setDraftKind(AgentActionDraftKind.jar);
          _commandController.clear();
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.text = config.jarPath.originalPath;
          _javaExecutablePathController.text = config.javaExecutablePath?.originalPath ?? '';
          _executableArgumentsController.text = config.arguments.join('\n');
          _workingDirectoryController.text = config.workingDirectory?.originalPath ?? '';
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.clear();
          _comMemberNameController.clear();
          _comArgumentsController.text = '{}';
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final EmailActionConfig config:
          _setDraftKind(AgentActionDraftKind.email);
          _commandController.clear();
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _workingDirectoryController.clear();
          _smtpProfileIdController.text = config.smtpProfileId;
          _emailFromController.text = config.from;
          _emailToController.text = config.to.join('\n');
          _emailCcController.text = config.cc.join('\n');
          _emailBccController.text = config.bcc.join('\n');
          _emailSubjectController.text = config.subjectTemplate;
          _emailBodyController.text = config.bodyTemplate;
          _emailAttachmentsController.text = config.attachmentPaths.map((path) => path.originalPath).join('\n');
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final ComObjectActionConfig config:
          _setDraftKind(AgentActionDraftKind.comObject);
          _commandController.clear();
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _workingDirectoryController.clear();
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.text = config.progId;
          _comMemberNameController.text = config.memberName;
          _comArgumentsController.text = const JsonEncoder.withIndent('  ').convert(config.arguments);
          _executorPathController.clear();
          _projectPathController.clear();
          _data7ConfigPathController.clear();
          _connectionIdController.clear();
          _connectionLabelController.clear();
          widget.provider.clearDeveloperData7Connections(notify: false);
        case final DeveloperActionConfig config:
          _setDraftKind(AgentActionDraftKind.developer);
          _commandController.clear();
          _executableTargetPathController.clear();
          _executableArgumentsController.clear();
          _scriptPathController.clear();
          _scriptInterpreterPathController.clear();
          _jarPathController.clear();
          _javaExecutablePathController.clear();
          _workingDirectoryController.clear();
          _smtpProfileIdController.clear();
          _emailFromController.clear();
          _emailToController.clear();
          _emailCcController.clear();
          _emailBccController.clear();
          _emailSubjectController.clear();
          _emailBodyController.clear();
          _emailAttachmentsController.clear();
          _comProgIdController.clear();
          _comMemberNameController.clear();
          _comArgumentsController.text = '{}';
          _executorPathController.text = config.executorPath.originalPath;
          _projectPathController.text = config.projectPath.originalPath;
          _data7ConfigPathController.text = config.data7ConfigPath.originalPath;
          _connectionIdController.text = config.connectionId;
          _connectionLabelController.text = config.connectionLabel;
          _scheduleDeveloperConnectionReload(
            pathPolicy: definition.policies.path,
            selectedConnectionId: config.connectionId,
          );
      }
    } finally {
      _applyingLoadedDefinition = false;
    }
  }

  void _clearDraft([AgentActionDraftKind? draftKind]) {
    _editingActionId = null;
    _setDraftKind(draftKind ?? _draftKind);
    _powerShellExecutable = PowerShellExecutable.windowsPowerShell;
    _nameController.clear();
    _descriptionController.clear();
    _commandController.clear();
    _workingDirectoryController.clear();
    _executableTargetPathController.clear();
    _executableArgumentsController.clear();
    _scriptPathController.clear();
    _scriptInterpreterPathController.clear();
    _jarPathController.clear();
    _javaExecutablePathController.clear();
    _smtpProfileIdController.clear();
    _emailFromController.clear();
    _emailToController.clear();
    _emailCcController.clear();
    _emailBccController.clear();
    _emailSubjectController.clear();
    _emailBodyController.clear();
    _emailAttachmentsController.clear();
    _comProgIdController.clear();
    _comMemberNameController.clear();
    _comArgumentsController.text = '{}';
    _executorPathController.clear();
    _projectPathController.clear();
    _data7ConfigPathController.clear();
    _connectionIdController.clear();
    _connectionLabelController.clear();
    _state = AgentActionState.needsValidation;
    _isDraftModifiedSinceLoad = false;
    widget.dirtyNotifier?.value = false;
    _notifyOnSuccess = false;
    _notifyOnFailure = false;
    _notifyOnTimeout = false;
    _maxAttempts = 1;
    _allowRemoteRetry = false;
    _maxRuntimeMinutes = 30;
    _maxRuntimeMinutesController.text = '30';
    _killMainProcessOnTimeout = true;
    _allowedProfilesController.clear();
    _allowedEnvironmentVariableNamesController.clear();
    _environmentVariablesController.clear();
    _acceptedExitCodesController.text = '0';
    _onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
    _processWindowMode = AgentActionProcessWindowMode.normal;
    _stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    _stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    _captureStdout = true;
    _captureStderr = true;
    _redactBeforePersisting = true;
    _maxConcurrentController.text = '1';
    _maxQueuedController.text = '100';
    _concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
    _allowedWorkingDirectoriesController.clear();
    _allowedContextDirectoriesController.clear();
    _remoteEnabled = false;
    _remoteAdHoc = false;
    _remoteApprovalGranted = false;
    _runElevated = false;
    _validationMessage = null;
    widget.provider.clearDeveloperData7Connections(notify: false);
  }

  AgentActionRetryPolicy _draftRetryPolicy() {
    return AgentActionRetryPolicy(
      maxAttempts: _maxAttempts,
      allowRemote: _allowRemoteRetry,
    );
  }

  AgentActionTimeoutPolicy _draftTimeoutPolicy() {
    return AgentActionTimeoutPolicy(
      maxRuntime: Duration(minutes: _maxRuntimeMinutes),
      killMainProcessOnTimeout: _killMainProcessOnTimeout,
    );
  }

  AgentActionNotificationPolicy _draftNotificationPolicy() {
    return AgentActionNotificationPolicy(
      notifyOnSuccess: _notifyOnSuccess,
      notifyOnFailure: _notifyOnFailure,
      notifyOnTimeout: _notifyOnTimeout,
    );
  }

  AgentActionEnvironmentPolicy _draftEnvironmentPolicy() {
    return AgentActionEnvironmentPolicy(
      allowedProfiles: _parseAllowedProfiles(_allowedProfilesController.text),
      allowedVariableNames: _parseCommaSeparatedTokens(_allowedEnvironmentVariableNamesController.text),
      variables: _parseEnvironmentVariables(_environmentVariablesController.text),
    );
  }

  AgentActionExitCodePolicy _draftExitCodePolicy(Set<int> acceptedExitCodes) {
    return AgentActionExitCodePolicy(acceptedExitCodes: acceptedExitCodes);
  }

  AgentActionLifecyclePolicy _draftLifecyclePolicy() {
    return AgentActionLifecyclePolicy(onAppExit: _onAppExit);
  }

  AgentActionProcessPolicy _draftProcessPolicy() {
    return AgentActionProcessPolicy(windowMode: _processWindowMode);
  }

  AgentActionEncodingPolicy _draftEncodingPolicy() {
    return AgentActionEncodingPolicy(
      stdout: _stdoutEncodingMode,
      stderr: _stderrEncodingMode,
    );
  }

  AgentActionCapturePolicy _draftCapturePolicy() {
    return AgentActionCapturePolicy(
      captureStdout: _captureStdout,
      captureStderr: _captureStderr,
      redactBeforePersisting: _redactBeforePersisting,
    );
  }

  AgentActionQueuePolicy _draftQueuePolicy() {
    return AgentActionQueuePolicy(
      maxConcurrent: _parsePositiveInt(_maxConcurrentController.text) ?? 1,
      maxQueued: _parsePositiveInt(_maxQueuedController.text) ?? 100,
      concurrencyBehavior: _concurrencyBehavior,
    );
  }

  AgentActionPathPolicy _draftPathPolicy() {
    return AgentActionPathPolicy(
      allowedWorkingDirectories: _parseCommaSeparatedTokens(_allowedWorkingDirectoriesController.text),
      allowedContextDirectories: _parseCommaSeparatedTokens(_allowedContextDirectoriesController.text),
    );
  }

  bool get _draftRequiresProductionPathAllowlist {
    return switch (_draftType) {
      AgentActionType.commandLine || AgentActionType.executable || AgentActionType.script => true,
      _ => false,
    };
  }

  bool get _shouldShowProductionPathAllowlistWarning {
    if (!_operationalProfileResolver.isProductionProfile || !_draftRequiresProductionPathAllowlist) {
      return false;
    }

    return _draftPathPolicy().allowedWorkingDirectories.isEmpty;
  }

  Widget _buildPreflightGateInfoBar({required bool canSelectActiveState}) {
    final definition = widget.definition;
    if (canSelectActiveState) {
      if (definition == null || _isDraftModifiedSinceLoad) {
        return const SizedBox.shrink();
      }

      final expiresAt = widget.provider.preflightExpiresAtForDefinition(definition);
      if (expiresAt == null) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsPreflightValidTitle),
            content: Text(
              widget.l10n.agentActionsPreflightExpiresAt(
                DateFormat.yMMMd().add_jm().format(expiresAt.toLocal()),
              ),
            ),
            isLong: true,
          ),
        ],
      );
    }

    final isExpired =
        definition != null && !_isDraftModifiedSinceLoad && widget.provider.isPreflightExpiredForDefinition(definition);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          title: Text(
            isExpired ? widget.l10n.agentActionsPreflightExpiredTitle : widget.l10n.agentActionsPreflightRequiredTitle,
          ),
          content: Text(
            isExpired
                ? widget.l10n.agentActionsPreflightExpiredForActive
                : widget.l10n.agentActionsPreflightRequiredForActive,
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ],
    );
  }

  int? _parsePositiveInt(String input) => AgentActionDraftParsers.positiveInt(input);

  bool get _draftCapturesProcessOutput {
    return switch (_draftType) {
      AgentActionType.commandLine ||
      AgentActionType.executable ||
      AgentActionType.script ||
      AgentActionType.jar ||
      AgentActionType.developer => true,
      AgentActionType.email || AgentActionType.comObject => false,
    };
  }

  AgentActionElevatedPolicy _draftElevatedPolicy() {
    if (!widget.provider.isElevatedAgentActionsEnabled) {
      return const AgentActionElevatedPolicy();
    }
    return AgentActionElevatedPolicy(runElevated: _runElevated);
  }

  AgentActionContextPolicy _draftContextPolicy() {
    final schemaText = _runtimeParameterSchemaController.text.trim();
    if (schemaText.isEmpty) {
      return AgentActionContextPolicy(
        injectionMode: _contextInjectionMode,
      );
    }

    final decoded = jsonDecode(schemaText);
    if (decoded is! Map) {
      throw const FormatException('Runtime parameter schema must be a JSON object.');
    }

    return AgentActionContextPolicy(
      injectionMode: _contextInjectionMode,
      runtimeParameterSchema: decoded.cast<String, Object?>(),
    );
  }

  bool _validateDraftContextPolicy() {
    try {
      _draftContextPolicy();
      return true;
    } on FormatException {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormRuntimeParameterSchemaHint;
      });
      return false;
    }
  }

  bool _validateDraftEnvironmentPolicy() {
    try {
      final policy = _draftEnvironmentPolicy();
      final failure = _environmentResolver.validatePolicy(
        actionId: _editingActionId ?? 'draft',
        policy: policy,
      );
      if (failure != null) {
        setState(() {
          _validationMessage = failure.context['user_message'] as String? ?? failure.message;
        });
        return false;
      }
      return true;
    } on FormatException {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormEnvironmentVariablesInvalid;
      });
      return false;
    }
  }

  bool _validateDraftQueuePolicy() {
    if (_parsePositiveInt(_maxConcurrentController.text) == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidQueueLimits;
      });
      return false;
    }

    if (_parsePositiveInt(_maxQueuedController.text) == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidQueueLimits;
      });
      return false;
    }

    return true;
  }

  bool _validateDraftPolicies() {
    return _validateDraftContextPolicy() && _validateDraftEnvironmentPolicy() && _validateDraftQueuePolicy();
  }

  AgentActionRemotePolicy _draftRemotePolicy() {
    if (!_remoteEnabled) {
      return const AgentActionRemotePolicy();
    }

    final existing = widget.definition;
    final previous = existing?.policies.remote;
    final DateTime? approvedAt;
    if (!_remoteApprovalGranted) {
      approvedAt = null;
    } else if (previous?.approvedAt == null || (previous?.requiresReapproval ?? false)) {
      approvedAt = DateTime.now().toUtc();
    } else {
      approvedAt = previous!.approvedAt;
    }

    return AgentActionRemotePolicy(
      isEnabled: true,
      allowAdHoc: widget.provider.isRemoteAdHocAgentActionsEnabled && _remoteAdHoc,
      approvedBy: approvedAt == null ? null : (previous?.approvedBy ?? _localRemoteApprover),
      approvedAt: approvedAt,
      approvalReason: previous?.approvalReason,
      riskFingerprint: previous?.riskFingerprint,
      requiresReapproval: !_remoteApprovalGranted && (previous?.requiresReapproval ?? false),
    );
  }

  Set<String> _parseAllowedProfiles(String input) => AgentActionDraftParsers.commaSeparatedTokens(input);

  Set<String> _parseCommaSeparatedTokens(String input) => AgentActionDraftParsers.commaSeparatedTokens(input);

  Map<String, String> _parseEnvironmentVariables(String input) => AgentActionDraftParsers.environmentVariables(input);

  String _formatEnvironmentVariables(Map<String, String> variables) =>
      AgentActionDraftParsers.formatEnvironmentVariables(variables);

  Set<int>? _tryParseAcceptedExitCodes(String input) => AgentActionDraftParsers.acceptedExitCodes(input);

  List<String> _missingRequiredFieldLabels() {
    final fields = <String>[];
    if (_nameController.text.trim().isEmpty) {
      fields.add(widget.l10n.agentActionsFormName);
    }

    if (_draftKind == AgentActionDraftKind.powerShell) {
      switch (_powerShellMode) {
        case PowerShellDraftMode.inline:
          if (_commandController.text.trim().isEmpty) {
            fields.add(widget.l10n.agentActionsFormPowerShellCommand);
          }
        case PowerShellDraftMode.script:
          if (_scriptPathController.text.trim().isEmpty) {
            fields.add(widget.l10n.agentActionsFormPowerShellScriptPath);
          }
      }
      return fields;
    }

    switch (_draftType) {
      case AgentActionType.commandLine:
        if (_commandController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormCommand);
        }
      case AgentActionType.executable:
        if (_executableTargetPathController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormExecutablePath);
        }
      case AgentActionType.script:
        if (_scriptPathController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormScriptPath);
        }
      case AgentActionType.jar:
        if (_jarPathController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormJarPath);
        }
      case AgentActionType.email:
        if (_smtpProfileIdController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormSmtpProfileId);
        }
        if (_emailFromController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormEmailFrom);
        }
        if (_parseStructuredArguments(_emailToController.text).isEmpty) {
          fields.add(widget.l10n.agentActionsFormEmailTo);
        }
        if (_emailSubjectController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormEmailSubject);
        }
        if (_emailBodyController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormEmailBody);
        }
      case AgentActionType.comObject:
        if (_comProgIdController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormComProgId);
        }
        if (_comMemberNameController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormComMemberName);
        }
      case AgentActionType.developer:
        if (_executorPathController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormExecutorPath);
        }
        if (_projectPathController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormProjectPath);
        }
        if (_connectionIdController.text.trim().isEmpty) {
          fields.add(widget.l10n.agentActionsFormConnectionId);
        }
    }

    return fields;
  }

  String _requiredFieldsValidationMessage(List<String> fieldLabels) {
    return fieldLabels.map((label) => '- ${widget.l10n.formFieldRequired(label)}').join('\n');
  }

  Future<bool> _save() async {
    final missingRequiredFields = _missingRequiredFieldLabels();
    if (missingRequiredFields.isNotEmpty) {
      final message = _requiredFieldsValidationMessage(missingRequiredFields);
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    final acceptedExitCodes = _tryParseAcceptedExitCodes(_acceptedExitCodesController.text);
    if (acceptedExitCodes == null) {
      final message = widget.l10n.agentActionsFormInvalidExitCodes;
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    if (_remoteEnabled && !_remoteApprovalGranted) {
      final message = widget.l10n.agentActionsFormRemoteApprovalRequired;
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    if (_state == AgentActionState.active &&
        !widget.provider.canSetDefinitionActive(
          _editingActionId,
          draftModified: _isDraftModifiedSinceLoad,
        )) {
      final message = widget.l10n.agentActionsPreflightRequiredForActive;
      _setValidationMessage(message);
      return _showValidationDialog(message);
    }

    final saveRequest = switch (_draftKind) {
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
      final validationMessage = _validationMessage;
      if (validationMessage != null && validationMessage.isNotEmpty) {
        return _showValidationDialog(validationMessage);
      }
      return _showSaveFailureDialog();
    }

    setState(() {
      _validationMessage = null;
      _isDraftModifiedSinceLoad = false;
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
                _editingActionId == null ? _createTitle() : _editTitle(),
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
        if (_isDialogSectionVisible(0)) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final stackFields = constraints.maxWidth < 720;
              final nameField = AppTextField(
                label: widget.l10n.agentActionsFormName,
                controller: _nameController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
              );
              final isEditing = _editingActionId != null;
              final typeField = isEditing
                  ? AppTextField(
                      key: AgentActionEditorKeys.actionTypeDropdown,
                      label: widget.l10n.agentActionsFormType,
                      helpTitle: widget.l10n.agentActionsHelpTypeTitle,
                      helpMessage: widget.l10n.agentActionsHelpTypeMessage,
                      controller: _actionTypeDisplayController,
                      enabled: !saving,
                      readOnly: true,
                      textInputAction: TextInputAction.next,
                    )
                  : AppDropdown<AgentActionDraftKind>(
                      key: AgentActionEditorKeys.actionTypeDropdown,
                      label: widget.l10n.agentActionsFormType,
                      helpTitle: widget.l10n.agentActionsHelpTypeTitle,
                      helpMessage: widget.l10n.agentActionsHelpTypeMessage,
                      value: _draftKind,
                      items: _editableDraftKinds
                          .map(
                            (draftKind) {
                              final unavailable = _isDraftKindUnavailable(draftKind);
                              final label = _draftKindLabel(draftKind);
                              return ComboBoxItem<AgentActionDraftKind>(
                                value: draftKind,
                                enabled: !unavailable,
                                child: Text(
                                  unavailable ? '$label (${widget.l10n.agentActionsRiskRunnerUnavailable})' : label,
                                ),
                              );
                            },
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value == null || value == _draftKind) {
                                return;
                              }
                              setState(() {
                                _clearDraft(value);
                              });
                            },
                    );
              final canSelectActiveState = widget.provider.canSetDefinitionActive(
                _editingActionId,
                draftModified: _isDraftModifiedSinceLoad,
              );
              final stateField = AppDropdown<AgentActionState>(
                label: widget.l10n.agentActionsFormState,
                helpTitle: widget.l10n.agentActionsHelpStateTitle,
                helpMessage: widget.l10n.agentActionsHelpStateMessage,
                value: _state,
                items: AgentActionState.values
                    .map(
                      (state) => ComboBoxItem<AgentActionState>(
                        value: state,
                        enabled: state != AgentActionState.active || canSelectActiveState,
                        child: Text(agentActionEditorStateLabel(state, widget.l10n)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        if (value == AgentActionState.active && !canSelectActiveState) {
                          _setValidationMessage(widget.l10n.agentActionsPreflightRequiredForActive);
                          return;
                        }
                        setState(() {
                          _state = value;
                          _validationMessage = null;
                        });
                      },
              );
              final preflightGateInfoBar = _buildPreflightGateInfoBar(
                canSelectActiveState: canSelectActiveState,
              );

              if (stackFields) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nameField,
                    const SizedBox(height: AppSpacing.sm),
                    typeField,
                    const SizedBox(height: AppSpacing.sm),
                    stateField,
                    preflightGateInfoBar,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: nameField),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 220, child: typeField),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 220, child: stateField),
                    ],
                  ),
                  preflightGateInfoBar,
                ],
              );
            },
          ),
        ],
        if (_isDialogSectionVisible(1)) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: widget.l10n.agentActionsFormDescription,
            controller: _descriptionController,
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
            maxAttempts: _maxAttempts,
            maxRuntimeMinutesController: _maxRuntimeMinutesController,
            killMainProcessOnTimeout: _killMainProcessOnTimeout,
            allowRemoteRetry: _allowRemoteRetry,
            runElevated: _runElevated,
            contextInjectionMode: _contextInjectionMode,
            pathChangePolicy: _pathChangePolicy,
            runtimeParameterSchemaController: _runtimeParameterSchemaController,
            callbacks: AgentActionExecutionPoliciesCallbacks(
              onMaxAttemptsChanged: (value) => setState(() => _maxAttempts = value),
              onMaxRuntimeMinutesChanged: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed != null && parsed > 0) {
                  setState(() => _maxRuntimeMinutes = parsed);
                }
              },
              onKillOnTimeoutChanged: (value) => setState(() => _killMainProcessOnTimeout = value),
              onAllowRemoteRetryChanged: (value) => setState(() => _allowRemoteRetry = value),
              onRunElevatedChanged: (value) => unawaited(_onRunElevatedChanged(value)),
              onContextInjectionModeChanged: (value) => setState(() => _contextInjectionMode = value),
              onPathChangePolicyChanged: (value) => setState(() => _pathChangePolicy = value),
            ),
          ),
        ],
        if (_isDialogSectionVisible(3)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionRuntimePoliciesSection(
            l10n: widget.l10n,
            enabled: !saving && widget.provider.canSaveAction,
            currentProfile: _operationalProfileResolver.currentProfile,
            allowedProfilesController: _allowedProfilesController,
            allowedEnvironmentVariableNamesController: _allowedEnvironmentVariableNamesController,
            environmentVariablesController: _environmentVariablesController,
            maxConcurrentController: _maxConcurrentController,
            maxQueuedController: _maxQueuedController,
            concurrencyBehavior: _concurrencyBehavior,
            allowedWorkingDirectoriesController: _allowedWorkingDirectoriesController,
            allowedContextDirectoriesController: _allowedContextDirectoriesController,
            showProductionPathAllowlistWarning: _shouldShowProductionPathAllowlistWarning,
            capturesProcessOutput: _draftCapturesProcessOutput,
            processWindowMode: _processWindowMode,
            captureStdout: _captureStdout,
            captureStderr: _captureStderr,
            redactBeforePersisting: _redactBeforePersisting,
            stdoutEncodingMode: _stdoutEncodingMode,
            stderrEncodingMode: _stderrEncodingMode,
            acceptedExitCodesController: _acceptedExitCodesController,
            onAppExit: _onAppExit,
            callbacks: AgentActionRuntimePoliciesCallbacks(
              onConcurrencyBehaviorChanged: (value) => setState(() => _concurrencyBehavior = value),
              onProcessWindowModeChanged: (value) => setState(() => _processWindowMode = value),
              onCaptureStdoutChanged: (value) => setState(() => _captureStdout = value),
              onCaptureStderrChanged: (value) => setState(() => _captureStderr = value),
              onRedactBeforePersistingChanged: (value) => setState(() => _redactBeforePersisting = value),
              onStdoutEncodingModeChanged: (value) => setState(() => _stdoutEncodingMode = value),
              onStderrEncodingModeChanged: (value) => setState(() => _stderrEncodingMode = value),
              onOnAppExitChanged: (value) => setState(() => _onAppExit = value),
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
            remoteEnabled: _remoteEnabled,
            remoteAdHoc: _remoteAdHoc,
            remoteApprovalGranted: _remoteApprovalGranted,
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
            notifyOnSuccess: _notifyOnSuccess,
            notifyOnFailure: _notifyOnFailure,
            notifyOnTimeout: _notifyOnTimeout,
            onNotifyOnSuccessChanged: (value) => setState(() => _notifyOnSuccess = value),
            onNotifyOnFailureChanged: (value) => setState(() => _notifyOnFailure = value),
            onNotifyOnTimeoutChanged: (value) => setState(() => _notifyOnTimeout = value),
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
              controller: _dialogScrollController,
              child: ListView(
                controller: _dialogScrollController,
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
        _remoteEnabled = true;
        _remoteApprovalGranted = true;
      });
      return;
    }

    setState(() {
      _remoteEnabled = false;
      _remoteAdHoc = false;
      _remoteApprovalGranted = false;
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
      _remoteAdHoc = enabled;
    });
  }

  Future<void> _onRunElevatedChanged(bool enabled) async {
    if (!enabled) {
      setState(() {
        _runElevated = false;
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
      _runElevated = true;
    });
  }

  List<Widget> _buildDraftFields(bool saving) {
    if (_draftKind == AgentActionDraftKind.powerShell) {
      return _buildPowerShellDraftFields(saving);
    }

    final enabled = !saving && widget.provider.canSaveAction;
    return switch (_draftType) {
      AgentActionType.commandLine => <Widget>[
        AgentActionCommandLineFields(
          l10n: widget.l10n,
          enabled: enabled,
          commandController: _commandController,
          workingDirectoryController: _workingDirectoryController,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.executable => <Widget>[
        AgentActionExecutableFields(
          l10n: widget.l10n,
          enabled: enabled,
          executableTargetPathController: _executableTargetPathController,
          argumentsController: _executableArgumentsController,
          workingDirectoryController: _workingDirectoryController,
          onPickExecutablePath: _pickExecutableTargetPath,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.comObject => <Widget>[
        AgentActionComObjectFields(
          l10n: widget.l10n,
          enabled: enabled,
          comProgIdController: _comProgIdController,
          comMemberNameController: _comMemberNameController,
          comArgumentsController: _comArgumentsController,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.email => <Widget>[
        AgentActionEmailFields(
          l10n: widget.l10n,
          enabled: enabled,
          smtpProfileIdController: _smtpProfileIdController,
          fromController: _emailFromController,
          toController: _emailToController,
          ccController: _emailCcController,
          bccController: _emailBccController,
          subjectController: _emailSubjectController,
          bodyController: _emailBodyController,
          attachmentsController: _emailAttachmentsController,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.jar => <Widget>[
        AgentActionJarFields(
          l10n: widget.l10n,
          enabled: enabled,
          jarPathController: _jarPathController,
          javaExecutablePathController: _javaExecutablePathController,
          argumentsController: _executableArgumentsController,
          workingDirectoryController: _workingDirectoryController,
          onPickJarPath: _pickJarPath,
          onPickJavaExecutablePath: _pickJavaExecutablePath,
          onSubmitted: () => unawaited(_save()),
        ),
      ],
      AgentActionType.script => <Widget>[
        AgentActionScriptFields(
          l10n: widget.l10n,
          enabled: enabled,
          scriptPathController: _scriptPathController,
          interpreterPathController: _scriptInterpreterPathController,
          argumentsController: _executableArgumentsController,
          workingDirectoryController: _workingDirectoryController,
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
          executorPathController: _executorPathController,
          projectPathController: _projectPathController,
          data7ConfigPathController: _data7ConfigPathController,
          connectionIdController: _connectionIdController,
          connectionLabelController: _connectionLabelController,
          connectionSearchController: _developerConnectionSearchController,
          binaryPathHints: _buildDeveloperBinaryPathHints(),
          connectionStatus: _buildDeveloperConnectionStatus(),
          configPathHints: _buildDeveloperConfigPathHints(),
          resolvedConfigHints: _buildDeveloperResolvedConfigHints(),
          callbacks: AgentActionDeveloperFieldsCallbacks(
            onBinaryPathChanged: _handleDeveloperBinaryPathChanged,
            onPickExecutorPath: _pickDeveloperExecutorPath,
            onPickProjectPath: _pickDeveloperProjectPath,
            onApplyDefaultExecutorPath: _applyDefaultDeveloperExecutorPath,
            onReloadConnections: () => unawaited(_reloadDeveloperConnections(pathPolicy: _draftPathPolicy())),
            onConfigPathChanged: _handleDeveloperConfigPathChanged,
            onPickConfigPath: _pickDeveloperData7ConfigPath,
            onApplyDefaultConfigBinPath: _applyDefaultDeveloperData7ConfigBinPath,
            onApplyDefaultConfigRootPath: _applyDefaultDeveloperData7ConfigRootPath,
            onConnectionIdChanged: _handleDeveloperConnectionIdChanged,
            onConnectionSearchChanged: (value) => setState(() => _developerConnectionSearchQuery = value),
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
        isEditing: _editingActionId != null,
        mode: _powerShellMode,
        executable: _powerShellExecutable,
        isModeUnavailable: _isPowerShellModeUnavailable,
        modeDisplayController: _powerShellModeDisplayController,
        commandController: _commandController,
        scriptPathController: _scriptPathController,
        argumentsController: _executableArgumentsController,
        workingDirectoryController: _workingDirectoryController,
        modeDropdownKey: AgentActionEditorKeys.powerShellModeDropdown,
        executableDropdownKey: AgentActionEditorKeys.powerShellExecutableDropdown,
        onModeChanged: (value) => setState(() => _setPowerShellMode(value)),
        onExecutableChanged: (value) => setState(() => _powerShellExecutable = value),
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
        executorPath: _executorPathController.text.trim(),
        projectPath: _projectPathController.text.trim(),
        defaultExecutorPath: _defaultDeveloperExecutorPath,
        l10n: widget.l10n,
      ),
    );
  }

  List<Widget> _buildDeveloperConfigPathHints() {
    return _developerHintWrap(
      AgentActionDeveloperHints.configPathHints(
        configPath: _data7ConfigPathController.text.trim(),
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
        typedConfigPath: _data7ConfigPathController.text,
        l10n: widget.l10n,
      ),
    );
  }

  List<Widget> _buildDeveloperConnectionStatus() {
    final definition = widget.definition;
    if (definition == null || definition.config is! DeveloperActionConfig) {
      return const <Widget>[];
    }
    if (_draftType != AgentActionType.developer) {
      return const <Widget>[];
    }
    if (widget.provider.isLoadingDeveloperConnections) {
      return const <Widget>[];
    }

    final config = definition.config as DeveloperActionConfig;
    final selectedConnectionId = _connectionIdController.text.trim();
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
    final executablePath = _executableTargetPathController.text.trim();
    if (executablePath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutablePath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveExecutableAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      executablePath: executablePath,
      arguments: _parseStructuredArguments(_executableArgumentsController.text),
      workingDirectory: _workingDirectoryController.text,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      encodingPolicy: _draftEncodingPolicy(),
      capturePolicy: _draftCapturePolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<bool> _saveJarDraft() async {
    final jarPath = _jarPathController.text.trim();
    if (jarPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormJarPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveJarAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      jarPath: jarPath,
      javaExecutablePath: _javaExecutablePathController.text,
      arguments: _parseStructuredArguments(_executableArgumentsController.text),
      workingDirectory: _workingDirectoryController.text,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      encodingPolicy: _draftEncodingPolicy(),
      capturePolicy: _draftCapturePolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<bool> _saveEmailDraft() async {
    final smtpProfileId = _smtpProfileIdController.text.trim();
    if (smtpProfileId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormSmtpProfileId);
      });
      return false;
    }

    final from = _emailFromController.text.trim();
    if (from.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailFrom);
      });
      return false;
    }

    final to = _parseStructuredArguments(_emailToController.text);
    if (to.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailTo);
      });
      return false;
    }

    final subject = _emailSubjectController.text.trim();
    if (subject.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailSubject);
      });
      return false;
    }

    final body = _emailBodyController.text.trim();
    if (body.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormEmailBody);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    final attachmentPaths = _parseStructuredArguments(_emailAttachmentsController.text)
        .map(
          (path) => AgentActionPathReference(
            originalPath: path,
            pathChangePolicy: _pathChangePolicy,
          ),
        )
        .toList(growable: false);

    return widget.provider.saveEmailAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      cc: _parseStructuredArguments(_emailCcController.text),
      bcc: _parseStructuredArguments(_emailBccController.text),
      subjectTemplate: subject,
      bodyTemplate: body,
      attachmentPaths: attachmentPaths,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<bool> _saveComObjectDraft() async {
    final progId = _comProgIdController.text.trim();
    if (progId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComProgId);
      });
      return false;
    }

    final memberName = _comMemberNameController.text.trim();
    if (memberName.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormComMemberName);
      });
      return false;
    }

    final argumentsResult = _parseComObjectArguments(_comArgumentsController.text);
    if (argumentsResult == null) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormInvalidComArguments;
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveComObjectAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      progId: progId,
      memberName: memberName,
      arguments: argumentsResult,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  Map<String, Object?>? _parseComObjectArguments(String raw) => AgentActionDraftParsers.comObjectArguments(raw);

  Future<bool> _saveScriptDraft() async {
    final scriptPath = _scriptPathController.text.trim();
    if (scriptPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormScriptPath);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveScriptAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      scriptPath: scriptPath,
      interpreterPath: _scriptInterpreterPathController.text,
      arguments: _parseStructuredArguments(_executableArgumentsController.text),
      workingDirectory: _workingDirectoryController.text,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      encodingPolicy: _draftEncodingPolicy(),
      capturePolicy: _draftCapturePolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  List<String> _parseStructuredArguments(String raw) => AgentActionDraftParsers.structuredArguments(raw);

  Future<bool> _saveCommandLineDraft() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormCommand);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveCommandLineAction(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      command: command,
      workingDirectory: _workingDirectoryController.text,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      encodingPolicy: _draftEncodingPolicy(),
      capturePolicy: _draftCapturePolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<bool> _savePowerShellDraft() async {
    if (_isPowerShellModeUnavailable(_powerShellMode)) {
      setState(() {
        _validationMessage = widget.l10n.agentActionsFormPowerShellModeUnavailable;
      });
      return false;
    }

    switch (_powerShellMode) {
      case PowerShellDraftMode.inline:
        final command = _commandController.text.trim();
        if (command.isEmpty) {
          setState(() {
            _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormPowerShellCommand);
          });
          return false;
        }

        if (!_validateDraftPolicies()) {
          return false;
        }

        return widget.provider.saveCommandLineAction(
          actionId: _editingActionId,
          name: _nameController.text.trim(),
          description: _descriptionController.text,
          command: PowerShellCommandLine.wrapInlineCommand(
            command,
            executable: _powerShellExecutableName(_powerShellExecutable),
          ),
          workingDirectory: _workingDirectoryController.text,
          state: _state,
          notificationPolicy: _draftNotificationPolicy(),
          retryPolicy: _draftRetryPolicy(),
          timeoutPolicy: _draftTimeoutPolicy(),
          environmentPolicy: _draftEnvironmentPolicy(),
          exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
          processPolicy: _draftProcessPolicy(),
          encodingPolicy: _draftEncodingPolicy(),
          capturePolicy: _draftCapturePolicy(),
          lifecyclePolicy: _draftLifecyclePolicy(),
          remotePolicy: _draftRemotePolicy(),
          elevatedPolicy: _draftElevatedPolicy(),
          contextPolicy: _draftContextPolicy(),
          pathChangePolicy: _pathChangePolicy,
          queuePolicy: _draftQueuePolicy(),
          pathPolicy: _draftPathPolicy(),
        );
      case PowerShellDraftMode.script:
        final scriptPath = _scriptPathController.text.trim();
        if (scriptPath.isEmpty) {
          setState(() {
            _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormPowerShellScriptPath);
          });
          return false;
        }
        if (!PowerShellCommandLine.isPowerShellScriptPath(scriptPath)) {
          setState(() {
            _validationMessage = widget.l10n.agentActionsFormPowerShellScriptPathInvalid;
          });
          return false;
        }

        if (!_validateDraftPolicies()) {
          return false;
        }

        return widget.provider.saveScriptAction(
          actionId: _editingActionId,
          name: _nameController.text.trim(),
          description: _descriptionController.text,
          scriptPath: scriptPath,
          interpreterPath: _powerShellExecutable == PowerShellExecutable.powerShell7
              ? PowerShellCommandLine.powerShell7Executable
              : '',
          arguments: _parseStructuredArguments(_executableArgumentsController.text),
          workingDirectory: _workingDirectoryController.text,
          state: _state,
          notificationPolicy: _draftNotificationPolicy(),
          retryPolicy: _draftRetryPolicy(),
          timeoutPolicy: _draftTimeoutPolicy(),
          environmentPolicy: _draftEnvironmentPolicy(),
          exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
          processPolicy: _draftProcessPolicy(),
          encodingPolicy: _draftEncodingPolicy(),
          capturePolicy: _draftCapturePolicy(),
          lifecyclePolicy: _draftLifecyclePolicy(),
          remotePolicy: _draftRemotePolicy(),
          elevatedPolicy: _draftElevatedPolicy(),
          contextPolicy: _draftContextPolicy(),
          pathChangePolicy: _pathChangePolicy,
          queuePolicy: _draftQueuePolicy(),
          pathPolicy: _draftPathPolicy(),
        );
    }
  }

  Future<bool> _saveDeveloperDraft() async {
    final executorPath = _executorPathController.text.trim();
    if (executorPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormExecutorPath);
      });
      return false;
    }

    final projectPath = _projectPathController.text.trim();
    if (projectPath.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormProjectPath);
      });
      return false;
    }

    final connectionId = _connectionIdController.text.trim();
    if (connectionId.isEmpty) {
      setState(() {
        _validationMessage = widget.l10n.formFieldRequired(widget.l10n.agentActionsFormConnectionId);
      });
      return false;
    }

    if (!_validateDraftPolicies()) {
      return false;
    }

    return widget.provider.saveDeveloperData7Action(
      actionId: _editingActionId,
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      executorPath: executorPath,
      projectPath: projectPath,
      data7ConfigPath: _data7ConfigPathController.text,
      connectionId: connectionId,
      connectionLabel: _connectionLabelController.text,
      state: _state,
      notificationPolicy: _draftNotificationPolicy(),
      retryPolicy: _draftRetryPolicy(),
      timeoutPolicy: _draftTimeoutPolicy(),
      environmentPolicy: _draftEnvironmentPolicy(),
      exitCodePolicy: _draftExitCodePolicy(_tryParseAcceptedExitCodes(_acceptedExitCodesController.text)!),
      processPolicy: _draftProcessPolicy(),
      encodingPolicy: _draftEncodingPolicy(),
      capturePolicy: _draftCapturePolicy(),
      lifecyclePolicy: _draftLifecyclePolicy(),
      remotePolicy: _draftRemotePolicy(),
      elevatedPolicy: _draftElevatedPolicy(),
      contextPolicy: _draftContextPolicy(),
      pathChangePolicy: _pathChangePolicy,
      queuePolicy: _draftQueuePolicy(),
      pathPolicy: _draftPathPolicy(),
    );
  }

  String _createTitle() {
    return switch (_draftKind) {
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
    return switch (_draftKind) {
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
      if (!mounted || _draftType != AgentActionType.developer) {
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
    final actionId = (_editingActionId?.trim().isNotEmpty ?? false) ? _editingActionId!.trim() : 'developer-draft';
    await widget.provider.loadDeveloperData7Connections(
      actionId: actionId,
      data7ConfigPath: _data7ConfigPathController.text,
      selectedConnectionId: selectedConnectionId ?? _connectionIdController.text,
      pathPolicy: pathPolicy,
    );

    if (!mounted) {
      return;
    }

    final resolvedPath = widget.provider.resolvedDeveloperData7ConfigPath;
    final typedConfigPath = _data7ConfigPathController.text.trim();
    if (resolvedPath != null &&
        resolvedPath.isNotEmpty &&
        (typedConfigPath.isEmpty || widget.provider.usedDefaultDeveloperData7ConfigPath)) {
      _data7ConfigPathController.text = resolvedPath;
    }

    final selectedId = selectedConnectionId ?? _connectionIdController.text.trim();
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
      _connectionIdController.text = selectedOption.id;
      _connectionLabelController.text = selectedOption.label;
    });
  }

  void _handleDeveloperConfigPathChanged(String _) {
    widget.provider.clearDeveloperData7Connections(notify: false);
    setState(() {
      _connectionLabelController.clear();
      _developerConnectionSearchQuery = '';
      _developerConnectionSearchController.clear();
      _validationMessage = null;
    });
  }

  bool get _developerConnectionFilterHasNoMatches {
    final query = _developerConnectionSearchQuery.trim();
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
    final query = _developerConnectionSearchQuery.trim().toLowerCase();
    final matched = query.isEmpty
        ? all
        : all
              .where(
                (option) => option.id.toLowerCase().contains(query) || option.label.toLowerCase().contains(query),
              )
              .toList(growable: false);

    final selectedId = _connectionIdController.text.trim();
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
      _validationMessage = null;
    });
  }

  void _handleDeveloperConnectionIdChanged(String value) {
    final selectedOption = widget.provider.developerConnections
        .where((option) => option.id == value.trim())
        .firstOrNull;
    setState(() {
      _connectionLabelController.text = selectedOption?.label ?? '';
    });
  }

  Future<void> _pickJarPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseJarPath,
      allowedExtensions: const ['jar'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _jarPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickJavaExecutablePath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseJavaExecutablePath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _javaExecutablePathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickScriptPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseScriptPath,
      allowedExtensions: const ['ps1', 'bat', 'cmd', 'py'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _scriptPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickPowerShellScriptPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowsePowerShellScriptPath,
      allowedExtensions: const ['ps1'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _scriptPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickScriptInterpreterPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseInterpreterPath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _scriptInterpreterPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickExecutableTargetPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseExecutablePath,
      allowedExtensions: const ['exe', 'bat', 'cmd'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _executableTargetPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperExecutorPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseExecutorPath,
      allowedExtensions: const ['exe'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _executorPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  void _applyDefaultDeveloperExecutorPath() {
    setState(() {
      _executorPathController.text = _defaultDeveloperExecutorPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperProjectPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseProjectPath,
      allowedExtensions: const ['7proj'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _projectPathController.text = selectedPath;
      _validationMessage = null;
    });
  }

  Future<void> _pickDeveloperData7ConfigPath() async {
    final selectedPath = await _pickSingleFile(
      dialogTitle: widget.l10n.agentActionsFormBrowseData7ConfigPath,
      allowedExtensions: const ['config'],
    );
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      _data7ConfigPathController.text = selectedPath;
      _connectionIdController.clear();
      _connectionLabelController.clear();
      _validationMessage = null;
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await _reloadDeveloperConnections(
      pathPolicy: _draftPathPolicy(),
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
      _data7ConfigPathController.text = path;
      _connectionIdController.clear();
      _connectionLabelController.clear();
      _validationMessage = null;
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await _reloadDeveloperConnections(
      pathPolicy: _draftPathPolicy(),
    );
  }

  Future<String?> _pickSingleFile({
    required String dialogTitle,
    required List<String> allowedExtensions,
  }) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );
      return picked?.files.singleOrNull?.path;
    } on Exception {
      if (!mounted) {
        return null;
      }

      setState(() {
        _validationMessage = widget.l10n.agentActionsFormBrowseFileError;
      });
      return null;
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
