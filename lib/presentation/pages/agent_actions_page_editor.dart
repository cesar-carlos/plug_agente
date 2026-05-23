part of 'agent_actions_page.dart';

enum _AgentActionDraftKind {
  commandLine,
  executable,
  script,
  jar,
  email,
  comObject,
  developer,
  powerShell,
}

enum _PowerShellDraftMode {
  inline,
  script,
}

enum _PowerShellExecutable {
  windowsPowerShell,
  powerShell7,
}

abstract final class _AgentActionEditorKeys {
  static const ValueKey<String> actionTypeDropdown = ValueKey<String>('agent_action_editor_type_dropdown');
  static const ValueKey<String> powerShellModeDropdown = ValueKey<String>(
    'agent_action_editor_powershell_mode_dropdown',
  );
  static const ValueKey<String> powerShellExecutableDropdown = ValueKey<String>(
    'agent_action_editor_powershell_executable_dropdown',
  );
}

class _AgentActionEditor extends StatefulWidget {
  const _AgentActionEditor({
    required this.provider,
    required this.l10n,
    this.definition,
    this.showChrome = true,
    this.onSaved,
  });

  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;
  final bool showChrome;
  final VoidCallback? onSaved;

  @override
  State<_AgentActionEditor> createState() => _AgentActionEditorState();
}

class _AgentActionEditorState extends State<_AgentActionEditor> {
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
  _AgentActionDraftKind _draftKind = _AgentActionDraftKind.commandLine;
  AgentActionType _draftType = AgentActionType.commandLine;
  _PowerShellDraftMode _powerShellMode = _PowerShellDraftMode.inline;
  _PowerShellExecutable _powerShellExecutable = _PowerShellExecutable.windowsPowerShell;
  AgentActionState _state = AgentActionState.needsValidation;
  bool _isDraftModifiedSinceLoad = false;
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
  static const String _localRemoteApprover = 'local-ui';

  @override
  void initState() {
    super.initState();
    _attachDraftChangeListeners();
    _loadDefinition(widget.definition);
    _resetVisibleDialogSections();
  }

  @override
  void didUpdateWidget(_AgentActionEditor oldWidget) {
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
    if (_isDraftModifiedSinceLoad) {
      return;
    }

    setState(() {
      _isDraftModifiedSinceLoad = true;
      if (_state == AgentActionState.active) {
        _state = AgentActionState.needsValidation;
      }
    });
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

  AgentActionType _actionTypeForDraftKind(_AgentActionDraftKind draftKind) {
    return switch (draftKind) {
      _AgentActionDraftKind.commandLine => AgentActionType.commandLine,
      _AgentActionDraftKind.executable => AgentActionType.executable,
      _AgentActionDraftKind.script => AgentActionType.script,
      _AgentActionDraftKind.jar => AgentActionType.jar,
      _AgentActionDraftKind.email => AgentActionType.email,
      _AgentActionDraftKind.comObject => AgentActionType.comObject,
      _AgentActionDraftKind.developer => AgentActionType.developer,
      _AgentActionDraftKind.powerShell => switch (_powerShellMode) {
        _PowerShellDraftMode.inline => AgentActionType.commandLine,
        _PowerShellDraftMode.script => AgentActionType.script,
      },
    };
  }

  void _setDraftKind(_AgentActionDraftKind draftKind) {
    _draftKind = draftKind;
    if (draftKind == _AgentActionDraftKind.powerShell && _isPowerShellModeUnavailable(_powerShellMode)) {
      _powerShellMode = _defaultAvailablePowerShellMode();
    }
    _draftType = _actionTypeForDraftKind(draftKind);
    _syncReadOnlyDisplayControllers();
  }

  void _setPowerShellMode(_PowerShellDraftMode mode) {
    _powerShellMode = mode;
    _draftType = _actionTypeForDraftKind(_AgentActionDraftKind.powerShell);
    _syncReadOnlyDisplayControllers();
  }

  void _syncReadOnlyDisplayControllers() {
    _setControllerText(_actionTypeDisplayController, _draftKindLabel(_draftKind));
    _setControllerText(_powerShellModeDisplayController, _powerShellModeLabel(_powerShellMode));
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    controller.text = text;
  }

  String _powerShellExecutableName(_PowerShellExecutable executable) {
    return switch (executable) {
      _PowerShellExecutable.windowsPowerShell => PowerShellCommandLine.windowsPowerShellExecutable,
      _PowerShellExecutable.powerShell7 => PowerShellCommandLine.powerShell7Executable,
    };
  }

  String _draftKindLabel(_AgentActionDraftKind draftKind) {
    return switch (draftKind) {
      _AgentActionDraftKind.commandLine => _typeLabel(AgentActionType.commandLine, widget.l10n),
      _AgentActionDraftKind.executable => _typeLabel(AgentActionType.executable, widget.l10n),
      _AgentActionDraftKind.script => _typeLabel(AgentActionType.script, widget.l10n),
      _AgentActionDraftKind.jar => _typeLabel(AgentActionType.jar, widget.l10n),
      _AgentActionDraftKind.email => _typeLabel(AgentActionType.email, widget.l10n),
      _AgentActionDraftKind.comObject => _typeLabel(AgentActionType.comObject, widget.l10n),
      _AgentActionDraftKind.developer => _typeLabel(AgentActionType.developer, widget.l10n),
      _AgentActionDraftKind.powerShell => widget.l10n.agentActionsTypePowerShell,
    };
  }

  bool _isDraftKindUnavailable(_AgentActionDraftKind draftKind) {
    if (draftKind == _AgentActionDraftKind.powerShell) {
      return _PowerShellDraftMode.values.every(_isPowerShellModeUnavailable);
    }

    return widget.provider.isActionTypeUnavailable(_actionTypeForDraftKind(draftKind));
  }

  bool _isPowerShellModeUnavailable(_PowerShellDraftMode mode) {
    return switch (mode) {
      _PowerShellDraftMode.inline => widget.provider.isActionTypeUnavailable(AgentActionType.commandLine),
      _PowerShellDraftMode.script => widget.provider.isActionTypeUnavailable(AgentActionType.script),
    };
  }

  _PowerShellDraftMode _defaultAvailablePowerShellMode() {
    for (final mode in _PowerShellDraftMode.values) {
      if (!_isPowerShellModeUnavailable(mode)) {
        return mode;
      }
    }

    return _PowerShellDraftMode.inline;
  }

  void _loadDefinition(AgentActionDefinition? definition) {
    _validationMessage = null;
    _isDraftModifiedSinceLoad = false;
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
          _setDraftKind(_AgentActionDraftKind.commandLine);
          _commandController.text = config.command;
        } else {
          _powerShellMode = _PowerShellDraftMode.inline;
          _powerShellExecutable = PowerShellCommandLine.isPowerShell7Executable(powerShellCommand.executable)
              ? _PowerShellExecutable.powerShell7
              : _PowerShellExecutable.windowsPowerShell;
          _setDraftKind(_AgentActionDraftKind.powerShell);
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
        _setDraftKind(_AgentActionDraftKind.executable);
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
          _powerShellMode = _PowerShellDraftMode.script;
          _powerShellExecutable = PowerShellCommandLine.isPowerShell7Executable(config.interpreterPath?.originalPath)
              ? _PowerShellExecutable.powerShell7
              : _PowerShellExecutable.windowsPowerShell;
          _setDraftKind(_AgentActionDraftKind.powerShell);
        } else {
          _setDraftKind(_AgentActionDraftKind.script);
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
        _setDraftKind(_AgentActionDraftKind.jar);
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
        _setDraftKind(_AgentActionDraftKind.email);
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
        _setDraftKind(_AgentActionDraftKind.comObject);
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
        _setDraftKind(_AgentActionDraftKind.developer);
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
  }

  void _clearDraft([_AgentActionDraftKind? draftKind]) {
    _editingActionId = null;
    _setDraftKind(draftKind ?? _draftKind);
    _powerShellExecutable = _PowerShellExecutable.windowsPowerShell;
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

  int? _parsePositiveInt(String input) {
    final parsed = int.tryParse(input.trim());
    if (parsed == null || parsed < 1) {
      return null;
    }

    return parsed;
  }

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

  Set<String> _parseAllowedProfiles(String input) => _parseCommaSeparatedTokens(input);

  Set<String> _parseCommaSeparatedTokens(String input) {
    if (input.trim().isEmpty) {
      return const <String>{};
    }

    return input.split(',').map((String part) => part.trim()).where((String part) => part.isNotEmpty).toSet();
  }

  Map<String, String> _parseEnvironmentVariables(String input) {
    final variables = <String, String>{};
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        throw const FormatException('Invalid environment variable line.');
      }

      final name = line.substring(0, separatorIndex).trim();
      if (name.isEmpty) {
        throw const FormatException('Environment variable name is blank.');
      }

      variables[name] = line.substring(separatorIndex + 1);
    }

    return Map<String, String>.unmodifiable(variables);
  }

  String _formatEnvironmentVariables(Map<String, String> variables) {
    if (variables.isEmpty) {
      return '';
    }

    final names = variables.keys.toList()..sort();
    return names.map((String name) => '$name=${variables[name]}').join('\n');
  }

  Set<int>? _tryParseAcceptedExitCodes(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const <int>{0};
    }

    final codes = <int>{};
    for (final part in trimmed.split(',')) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final code = int.tryParse(token);
      if (code == null) {
        return null;
      }
      codes.add(code);
    }

    if (codes.isEmpty) {
      return const <int>{0};
    }

    return codes;
  }

  List<String> _missingRequiredFieldLabels() {
    final fields = <String>[];
    if (_nameController.text.trim().isEmpty) {
      fields.add(widget.l10n.agentActionsFormName);
    }

    if (_draftKind == _AgentActionDraftKind.powerShell) {
      switch (_powerShellMode) {
        case _PowerShellDraftMode.inline:
          if (_commandController.text.trim().isEmpty) {
            fields.add(widget.l10n.agentActionsFormPowerShellCommand);
          }
        case _PowerShellDraftMode.script:
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
      _AgentActionDraftKind.commandLine => _saveCommandLineDraft(),
      _AgentActionDraftKind.executable => _saveExecutableDraft(),
      _AgentActionDraftKind.script => _saveScriptDraft(),
      _AgentActionDraftKind.jar => _saveJarDraft(),
      _AgentActionDraftKind.email => _saveEmailDraft(),
      _AgentActionDraftKind.comObject => _saveComObjectDraft(),
      _AgentActionDraftKind.developer => _saveDeveloperDraft(),
      _AgentActionDraftKind.powerShell => _savePowerShellDraft(),
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
                      key: _AgentActionEditorKeys.actionTypeDropdown,
                      label: widget.l10n.agentActionsFormType,
                      helpTitle: widget.l10n.agentActionsHelpTypeTitle,
                      helpMessage: widget.l10n.agentActionsHelpTypeMessage,
                      controller: _actionTypeDisplayController,
                      enabled: !saving,
                      readOnly: true,
                      textInputAction: TextInputAction.next,
                    )
                  : AppDropdown<_AgentActionDraftKind>(
                      key: _AgentActionEditorKeys.actionTypeDropdown,
                      label: widget.l10n.agentActionsFormType,
                      helpTitle: widget.l10n.agentActionsHelpTypeTitle,
                      helpMessage: widget.l10n.agentActionsHelpTypeMessage,
                      value: _draftKind,
                      items: _editableDraftKinds
                          .map(
                            (draftKind) {
                              final unavailable = _isDraftKindUnavailable(draftKind);
                              final label = _draftKindLabel(draftKind);
                              return ComboBoxItem<_AgentActionDraftKind>(
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
                        child: Text(_stateLabel(state, widget.l10n)),
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
              final preflightGateInfoBar = !canSelectActiveState
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        InfoBar(
                          title: Text(widget.l10n.agentActionsPreflightRequiredTitle),
                          content: Text(widget.l10n.agentActionsPreflightRequiredForActive),
                          severity: InfoBarSeverity.warning,
                          isLong: true,
                        ),
                      ],
                    )
                  : const SizedBox.shrink();

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
          _buildExecutionPoliciesSection(saving),
        ],
        if (_isDialogSectionVisible(3)) ...[
          const SizedBox(height: AppSpacing.md),
          _buildRuntimePoliciesSection(saving),
        ],
        if (_isDialogSectionVisible(4)) ...[
          const SizedBox(height: AppSpacing.md),
          _buildRemotePolicySection(saving),
        ],
        if (_isDialogSectionVisible(5)) ...[
          const SizedBox(height: AppSpacing.md),
          _buildNotificationPolicySection(saving),
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

  Widget _buildExecutionPoliciesSection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormExecutionPoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormExecutionPoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: AppDropdown<int>(
                label: widget.l10n.agentActionsFormMaxAttempts,
                helpTitle: widget.l10n.agentActionsHelpMaxAttemptsTitle,
                helpMessage: widget.l10n.agentActionsHelpMaxAttemptsMessage,
                value: _maxAttempts,
                items: List<ComboBoxItem<int>>.generate(
                  5,
                  (int index) {
                    final attempts = index + 1;
                    return ComboBoxItem<int>(
                      value: attempts,
                      child: Text('$attempts'),
                    );
                  },
                  growable: false,
                ),
                onChanged: enabled
                    ? (int? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _maxAttempts = value;
                        });
                      }
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormMaxRuntimeMinutes,
                helpTitle: widget.l10n.agentActionsHelpTimeoutTitle,
                helpMessage: widget.l10n.agentActionsHelpTimeoutMessage,
                controller: _maxRuntimeMinutesController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: (String value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null && parsed > 0) {
                    setState(() {
                      _maxRuntimeMinutes = parsed;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _killMainProcessOnTimeout,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _killMainProcessOnTimeout = value ?? true;
                      });
                    }
                  : null,
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormKillOnTimeout,
                helpTitle: widget.l10n.agentActionsHelpKillOnTimeoutTitle,
                helpMessage: widget.l10n.agentActionsHelpKillOnTimeoutMessage,
              ),
            ),
            Checkbox(
              checked: _allowRemoteRetry,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _allowRemoteRetry = value ?? false;
                      });
                    }
                  : null,
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormAllowRemoteRetry,
                helpTitle: widget.l10n.agentActionsHelpRemoteRetryTitle,
                helpMessage: widget.l10n.agentActionsHelpRemoteRetryMessage,
              ),
            ),
            if (widget.provider.isElevatedAgentActionsEnabled)
              Checkbox(
                checked: _runElevated,
                onChanged:
                    enabled && widget.provider.isElevatedRunnerConfigured && !widget.provider.isElevatedRunnerDegraded
                    ? (bool? value) {
                        unawaited(_onRunElevatedChanged(value ?? false));
                      }
                    : null,
                content: _HelpCheckboxLabel(
                  label: widget.l10n.agentActionsFormRunElevated,
                  helpTitle: widget.l10n.agentActionsHelpRunElevatedTitle,
                  helpMessage: widget.l10n.agentActionsHelpRunElevatedMessage,
                ),
              ),
          ],
        ),
        if (widget.provider.isElevatedAgentActionsEnabled) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.l10n.agentActionsFormRunElevatedHint,
            style: context.bodyMuted,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppDropdown<AgentActionContextInjectionMode>(
          label: widget.l10n.agentActionsFormContextInjectionMode,
          helpTitle: widget.l10n.agentActionsHelpContextInjectionTitle,
          helpMessage: widget.l10n.agentActionsHelpContextInjectionMessage,
          value: _contextInjectionMode,
          items: [
            ComboBoxItem(
              value: AgentActionContextInjectionMode.argument,
              child: Text(widget.l10n.agentActionsFormContextInjectionArgument),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.file,
              child: Text(widget.l10n.agentActionsFormContextInjectionFile),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.environment,
              child: Text(widget.l10n.agentActionsFormContextInjectionEnvironment),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.stdin,
              child: Text(widget.l10n.agentActionsFormContextInjectionStdin),
            ),
          ],
          onChanged: enabled
              ? (AgentActionContextInjectionMode? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _contextInjectionMode = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionPathChangePolicy>(
          label: widget.l10n.agentActionsFormPathChangePolicy,
          helpTitle: widget.l10n.agentActionsHelpPathChangePolicyTitle,
          helpMessage: widget.l10n.agentActionsHelpPathChangePolicyMessage,
          value: _pathChangePolicy,
          items: [
            ComboBoxItem(
              value: AgentActionPathChangePolicy.failIfChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyFail),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.warnIfChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyWarn),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.allowChanged,
              child: Text(widget.l10n.agentActionsFormPathChangePolicyAllow),
            ),
          ],
          onChanged: enabled
              ? (AgentActionPathChangePolicy? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _pathChangePolicy = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormRuntimeParameterSchema,
          helpTitle: widget.l10n.agentActionsHelpRuntimeSchemaTitle,
          helpMessage: widget.l10n.agentActionsHelpRuntimeSchemaMessage,
          controller: _runtimeParameterSchemaController,
          enabled: enabled,
          maxLines: 6,
          hint: widget.l10n.agentActionsFormRuntimeParameterSchemaHint,
        ),
      ],
    );
  }

  Widget _buildRuntimePoliciesSection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    final currentProfile = _operationalProfileResolver.currentProfile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormRuntimePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormRuntimePoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          title: Text(
            currentProfile == null
                ? widget.l10n.agentActionsFormCurrentOperationalProfileUnset
                : widget.l10n.agentActionsFormCurrentOperationalProfile(currentProfile),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedProfiles,
          helpTitle: widget.l10n.agentActionsHelpAllowedProfilesTitle,
          helpMessage: widget.l10n.agentActionsHelpAllowedProfilesMessage,
          controller: _allowedProfilesController,
          enabled: enabled,
          hint: widget.l10n.agentActionsFormAllowedProfilesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedEnvironmentVariableNames,
          helpTitle: widget.l10n.agentActionsHelpAllowedEnvironmentVariablesTitle,
          helpMessage: widget.l10n.agentActionsHelpAllowedEnvironmentVariablesMessage,
          controller: _allowedEnvironmentVariableNamesController,
          enabled: enabled,
          hint: widget.l10n.agentActionsFormAllowedEnvironmentVariableNamesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEnvironmentVariables,
          helpTitle: widget.l10n.agentActionsHelpEnvironmentVariablesTitle,
          helpMessage: widget.l10n.agentActionsHelpEnvironmentVariablesMessage,
          controller: _environmentVariablesController,
          enabled: enabled,
          maxLines: 6,
          hint: widget.l10n.agentActionsFormEnvironmentVariablesHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.l10n.agentActionsFormQueuePolicyDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final maxConcurrentField = AppTextField(
              label: widget.l10n.agentActionsFormMaxConcurrent,
              helpTitle: widget.l10n.agentActionsHelpQueueTitle,
              helpMessage: widget.l10n.agentActionsHelpQueueMessage,
              controller: _maxConcurrentController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );
            final maxQueuedField = AppTextField(
              label: widget.l10n.agentActionsFormMaxQueued,
              helpTitle: widget.l10n.agentActionsHelpQueueTitle,
              helpMessage: widget.l10n.agentActionsHelpQueueMessage,
              controller: _maxQueuedController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  maxConcurrentField,
                  const SizedBox(height: AppSpacing.sm),
                  maxQueuedField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: maxConcurrentField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: maxQueuedField),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionConcurrencyBehavior>(
          label: widget.l10n.agentActionsFormConcurrencyBehavior,
          helpTitle: widget.l10n.agentActionsHelpQueueTitle,
          helpMessage: widget.l10n.agentActionsHelpQueueMessage,
          value: _concurrencyBehavior,
          items: AgentActionConcurrencyBehavior.values
              .map(
                (AgentActionConcurrencyBehavior behavior) => ComboBoxItem<AgentActionConcurrencyBehavior>(
                  value: behavior,
                  child: Text(_concurrencyBehaviorLabel(behavior, widget.l10n)),
                ),
              )
              .toList(growable: false),
          onChanged: enabled
              ? (AgentActionConcurrencyBehavior? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _concurrencyBehavior = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.l10n.agentActionsFormPathAllowlistDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedWorkingDirectories,
          helpTitle: widget.l10n.agentActionsHelpPathAllowlistTitle,
          helpMessage: widget.l10n.agentActionsHelpPathAllowlistMessage,
          controller: _allowedWorkingDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: widget.l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormAllowedContextDirectories,
          helpTitle: widget.l10n.agentActionsHelpPathAllowlistTitle,
          helpMessage: widget.l10n.agentActionsHelpPathAllowlistMessage,
          controller: _allowedContextDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: widget.l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_draftCapturesProcessOutput) ...[
          AppDropdown<AgentActionProcessWindowMode>(
            label: widget.l10n.agentActionsFormProcessWindowMode,
            helpTitle: widget.l10n.agentActionsHelpProcessWindowTitle,
            helpMessage: widget.l10n.agentActionsHelpProcessWindowMessage,
            value: _processWindowMode,
            items: AgentActionProcessWindowMode.values
                .map(
                  (AgentActionProcessWindowMode mode) => ComboBoxItem<AgentActionProcessWindowMode>(
                    value: mode,
                    child: Text(_processWindowModeLabel(mode, widget.l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: enabled
                ? (AgentActionProcessWindowMode? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _processWindowMode = value;
                    });
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.l10n.agentActionsFormCapturePolicyDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Checkbox(
                checked: _captureStdout,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _captureStdout = value ?? true;
                        });
                      }
                    : null,
                content: _HelpCheckboxLabel(
                  label: widget.l10n.agentActionsFormCaptureStdout,
                  helpTitle: widget.l10n.agentActionsHelpCaptureTitle,
                  helpMessage: widget.l10n.agentActionsHelpCaptureMessage,
                ),
              ),
              Checkbox(
                checked: _captureStderr,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _captureStderr = value ?? true;
                        });
                      }
                    : null,
                content: _HelpCheckboxLabel(
                  label: widget.l10n.agentActionsFormCaptureStderr,
                  helpTitle: widget.l10n.agentActionsHelpCaptureTitle,
                  helpMessage: widget.l10n.agentActionsHelpCaptureMessage,
                ),
              ),
              Checkbox(
                checked: _redactBeforePersisting,
                onChanged: enabled
                    ? (bool? value) {
                        setState(() {
                          _redactBeforePersisting = value ?? true;
                        });
                      }
                    : null,
                content: _HelpCheckboxLabel(
                  label: widget.l10n.agentActionsFormRedactBeforePersisting,
                  helpTitle: widget.l10n.agentActionsHelpCaptureTitle,
                  helpMessage: widget.l10n.agentActionsHelpCaptureMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.l10n.agentActionsFormOutputEncodingDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: widget.l10n.agentActionsFormStdoutEncoding,
                  helpTitle: widget.l10n.agentActionsHelpEncodingTitle,
                  helpMessage: widget.l10n.agentActionsHelpEncodingMessage,
                  value: _stdoutEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(_outputEncodingModeLabel(mode, widget.l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _stdoutEncodingMode = value;
                          });
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: widget.l10n.agentActionsFormStderrEncoding,
                  helpTitle: widget.l10n.agentActionsHelpEncodingTitle,
                  helpMessage: widget.l10n.agentActionsHelpEncodingMessage,
                  value: _stderrEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(_outputEncodingModeLabel(mode, widget.l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _stderrEncodingMode = value;
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final exitCodesField = AppTextField(
              label: widget.l10n.agentActionsFormAcceptedExitCodes,
              helpTitle: widget.l10n.agentActionsHelpAcceptedExitCodesTitle,
              helpMessage: widget.l10n.agentActionsHelpAcceptedExitCodesMessage,
              controller: _acceptedExitCodesController,
              enabled: enabled,
              hint: widget.l10n.agentActionsFormAcceptedExitCodesHint,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
            );
            final onAppExitField = AppDropdown<AgentActionOnAppExitBehavior>(
              label: widget.l10n.agentActionsFormOnAppExit,
              helpTitle: widget.l10n.agentActionsHelpOnAppExitTitle,
              helpMessage: widget.l10n.agentActionsHelpOnAppExitMessage,
              value: _onAppExit,
              items: AgentActionOnAppExitBehavior.values
                  .map(
                    (AgentActionOnAppExitBehavior behavior) => ComboBoxItem<AgentActionOnAppExitBehavior>(
                      value: behavior,
                      child: Text(_onAppExitLabel(behavior, widget.l10n)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (AgentActionOnAppExitBehavior? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _onAppExit = value;
                      });
                    }
                  : null,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  exitCodesField,
                  const SizedBox(height: AppSpacing.sm),
                  onAppExitField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: exitCodesField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 280, child: onAppExitField),
              ],
            );
          },
        ),
      ],
    );
  }

  String _onAppExitLabel(AgentActionOnAppExitBehavior behavior, AppLocalizations l10n) {
    return switch (behavior) {
      AgentActionOnAppExitBehavior.killMainProcess => l10n.agentActionsFormOnAppExitKill,
      AgentActionOnAppExitBehavior.waitThenKillMainProcess => l10n.agentActionsFormOnAppExitWaitThenKill,
      AgentActionOnAppExitBehavior.leaveRunning => l10n.agentActionsFormOnAppExitLeaveRunning,
    };
  }

  String _processWindowModeLabel(AgentActionProcessWindowMode mode, AppLocalizations l10n) {
    return switch (mode) {
      AgentActionProcessWindowMode.normal => l10n.agentActionsFormProcessWindowModeNormal,
      AgentActionProcessWindowMode.hidden => l10n.agentActionsFormProcessWindowModeHidden,
      AgentActionProcessWindowMode.minimized => l10n.agentActionsFormProcessWindowModeMinimized,
    };
  }

  String _concurrencyBehaviorLabel(AgentActionConcurrencyBehavior behavior, AppLocalizations l10n) {
    return switch (behavior) {
      AgentActionConcurrencyBehavior.allowParallel => l10n.agentActionsFormConcurrencyAllowParallel,
      AgentActionConcurrencyBehavior.enqueue => l10n.agentActionsFormConcurrencyEnqueue,
      AgentActionConcurrencyBehavior.reject => l10n.agentActionsFormConcurrencyReject,
      AgentActionConcurrencyBehavior.ignore => l10n.agentActionsFormConcurrencyIgnore,
    };
  }

  String _outputEncodingModeLabel(AgentActionOutputEncodingMode mode, AppLocalizations l10n) {
    return switch (mode) {
      AgentActionOutputEncodingMode.utf8 => l10n.agentActionsFormOutputEncodingUtf8,
      AgentActionOutputEncodingMode.systemConsole => l10n.agentActionsFormOutputEncodingSystemConsole,
    };
  }

  Widget _buildRemotePolicySection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    final remoteFeatureEnabled = widget.provider.isRemoteAgentActionsEnabled;
    final remoteAdHocFeatureEnabled = widget.provider.isRemoteAdHocAgentActionsEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormRemotePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormRemotePoliciesDescription,
          style: context.bodyMuted,
        ),
        if (!remoteFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsFormRemoteFeatureDisabledTitle),
            content: Text(widget.l10n.agentActionsFormRemoteFeatureDisabledMessage),
            isLong: true,
          ),
        ] else if (!remoteAdHocFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsFormRemoteAdHocFeatureDisabledTitle),
            content: Text(widget.l10n.agentActionsFormRemoteAdHocFeatureDisabledMessage),
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _remoteEnabled,
              onChanged: !enabled
                  ? null
                  : (bool? value) {
                      unawaited(_onRemoteEnabledChanged(value ?? false));
                    },
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormRemoteExecutionEnabled,
                helpTitle: widget.l10n.agentActionsHelpRemoteExecutionTitle,
                helpMessage: widget.l10n.agentActionsHelpRemoteExecutionMessage,
              ),
            ),
            Checkbox(
              checked: _remoteAdHoc,
              onChanged: !enabled || !_remoteEnabled || !remoteAdHocFeatureEnabled
                  ? null
                  : (bool? value) {
                      unawaited(_onRemoteAdHocChanged(value ?? false));
                    },
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormRemoteAdHocEnabled,
                helpTitle: widget.l10n.agentActionsHelpRemoteAdHocTitle,
                helpMessage: widget.l10n.agentActionsHelpRemoteAdHocMessage,
              ),
            ),
          ],
        ),
        if (widget.definition?.policies.remote.requiresReapproval ?? false) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            key: _AgentActionsPageKeys.remoteReapprovalInfoBar,
            title: Text(widget.l10n.agentActionsFormRemoteReapprovalRequiredTitle),
            content: Text(widget.l10n.agentActionsFormRemoteReapprovalRequiredMessage),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ] else if (_remoteEnabled && _remoteApprovalGranted) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.l10n.agentActionsFormRemoteApprovedHint,
            style: context.bodyMuted,
          ),
        ],
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

  Widget _buildNotificationPolicySection(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.l10n.agentActionsFormNotificationsTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.l10n.agentActionsFormNotificationsDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: _notifyOnSuccess,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnSuccess = value ?? false;
                      });
                    }
                  : null,
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormNotifyOnSuccess,
                helpTitle: widget.l10n.agentActionsHelpNotificationsTitle,
                helpMessage: widget.l10n.agentActionsHelpNotificationsMessage,
              ),
            ),
            Checkbox(
              checked: _notifyOnFailure,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnFailure = value ?? false;
                      });
                    }
                  : null,
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormNotifyOnFailure,
                helpTitle: widget.l10n.agentActionsHelpNotificationsTitle,
                helpMessage: widget.l10n.agentActionsHelpNotificationsMessage,
              ),
            ),
            Checkbox(
              checked: _notifyOnTimeout,
              onChanged: enabled
                  ? (bool? value) {
                      setState(() {
                        _notifyOnTimeout = value ?? false;
                      });
                    }
                  : null,
              content: _HelpCheckboxLabel(
                label: widget.l10n.agentActionsFormNotifyOnTimeout,
                helpTitle: widget.l10n.agentActionsHelpNotificationsTitle,
                helpMessage: widget.l10n.agentActionsHelpNotificationsMessage,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildDraftFields(bool saving) {
    if (_draftKind == _AgentActionDraftKind.powerShell) {
      return _buildPowerShellDraftFields(saving);
    }

    return switch (_draftType) {
      AgentActionType.commandLine => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormCommand,
          helpTitle: widget.l10n.agentActionsHelpCommandTitle,
          helpMessage: widget.l10n.agentActionsHelpCommandMessage,
          controller: _commandController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 2,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          helpTitle: widget.l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: widget.l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.executable => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormExecutablePath,
          helpTitle: widget.l10n.agentActionsHelpPathTitle,
          helpMessage: widget.l10n.agentActionsHelpPathMessage,
          controller: _executableTargetPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickExecutableTargetPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          helpTitle: widget.l10n.agentActionsHelpArgumentsTitle,
          helpMessage: widget.l10n.agentActionsHelpArgumentsMessage,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          helpTitle: widget.l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: widget.l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.comObject => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormComProgId,
          helpTitle: widget.l10n.agentActionsHelpComTitle,
          helpMessage: widget.l10n.agentActionsHelpComMessage,
          controller: _comProgIdController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormComMemberName,
          helpTitle: widget.l10n.agentActionsHelpComTitle,
          helpMessage: widget.l10n.agentActionsHelpComMessage,
          controller: _comMemberNameController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormComArguments,
          helpTitle: widget.l10n.agentActionsHelpComTitle,
          helpMessage: widget.l10n.agentActionsHelpComMessage,
          controller: _comArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 8,
          textInputAction: TextInputAction.done,
          hint: widget.l10n.agentActionsFormComArgumentsHint,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.email => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormSmtpProfileId,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _smtpProfileIdController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormSmtpProfileIdHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailFrom,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailFromController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailTo,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailToController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailToHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailCc,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailCcController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailCcHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailBcc,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailBccController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailBccHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailSubject,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailSubjectController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailSubjectHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailBody,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailBodyController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 8,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormEmailBodyHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormEmailAttachments,
          helpTitle: widget.l10n.agentActionsHelpEmailTitle,
          helpMessage: widget.l10n.agentActionsHelpEmailMessage,
          controller: _emailAttachmentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          hint: widget.l10n.agentActionsFormEmailAttachmentsHint,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.jar => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormJarPath,
          helpTitle: widget.l10n.agentActionsHelpJarTitle,
          helpMessage: widget.l10n.agentActionsHelpJarMessage,
          controller: _jarPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseJarPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickJarPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormJavaExecutablePath,
          helpTitle: widget.l10n.agentActionsHelpInterpreterTitle,
          helpMessage: widget.l10n.agentActionsHelpInterpreterMessage,
          controller: _javaExecutablePathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormJavaExecutablePathHint,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseJavaExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickJavaExecutablePath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          helpTitle: widget.l10n.agentActionsHelpArgumentsTitle,
          helpMessage: widget.l10n.agentActionsHelpArgumentsMessage,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          helpTitle: widget.l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: widget.l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.script => <Widget>[
        AppTextField(
          label: widget.l10n.agentActionsFormScriptPath,
          helpTitle: widget.l10n.agentActionsHelpPathTitle,
          helpMessage: widget.l10n.agentActionsHelpPathMessage,
          controller: _scriptPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseScriptPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickScriptPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormInterpreterPath,
          helpTitle: widget.l10n.agentActionsHelpInterpreterTitle,
          helpMessage: widget.l10n.agentActionsHelpInterpreterMessage,
          controller: _scriptInterpreterPathController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormInterpreterPathHint,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowseInterpreterPath,
            icon: FluentIcons.open_file,
            onPressed: saving || !widget.provider.canSaveAction ? null : _pickScriptInterpreterPath,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          helpTitle: widget.l10n.agentActionsHelpArgumentsTitle,
          helpMessage: widget.l10n.agentActionsHelpArgumentsMessage,
          controller: _executableArgumentsController,
          enabled: !saving && widget.provider.canSaveAction,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormWorkingDirectory,
          helpTitle: widget.l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: widget.l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: _workingDirectoryController,
          enabled: !saving && widget.provider.canSaveAction,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
      AgentActionType.developer => <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormExecutorPath,
                helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
                helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
                controller: _executorPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperBinaryPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseExecutorPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperExecutorPath,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormProjectPath,
                helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
                helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
                controller: _projectPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperBinaryPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseProjectPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperProjectPath,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _DeveloperPathShortcuts(
          primaryLabel: widget.l10n.agentActionsFormUseDefaultExecutorPath,
          onPrimaryPressed: saving || !widget.provider.canSaveAction ? null : _applyDefaultDeveloperExecutorPath,
        ),
        ..._buildDeveloperBinaryPathHints(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Button(
              onPressed: saving || !widget.provider.canSaveAction || widget.provider.isLoadingDeveloperConnections
                  ? null
                  : () {
                      unawaited(
                        _reloadDeveloperConnections(
                          pathPolicy: _draftPathPolicy(),
                        ),
                      );
                    },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.provider.isLoadingDeveloperConnections)
                    const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.refresh),
                  const SizedBox(width: AppSpacing.xs),
                  Text(widget.l10n.agentActionsFormReloadConnections),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (widget.provider.usedDefaultDeveloperData7ConfigPath)
              Expanded(
                child: Text(
                  widget.l10n.agentActionsFormDefaultConfigResolved,
                  style: context.bodyMuted,
                ),
              ),
          ],
        ),
        if (widget.provider.developerConnectionLookupMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(widget.l10n.agentActionsValidationTitle),
            content: Text(widget.provider.developerConnectionLookupMessage!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        ..._buildDeveloperConnectionStatus(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormData7ConfigPath,
                helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
                helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
                controller: _data7ConfigPathController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperConfigPathChanged,
                suffixIcon: _PathPickerButton(
                  tooltip: widget.l10n.agentActionsFormBrowseData7ConfigPath,
                  icon: FluentIcons.open_file,
                  onPressed: saving || !widget.provider.canSaveAction ? null : _pickDeveloperData7ConfigPath,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: widget.l10n.agentActionsFormConnectionId,
                helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
                helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
                controller: _connectionIdController,
                enabled: !saving && widget.provider.canSaveAction,
                textInputAction: TextInputAction.next,
                onChanged: _handleDeveloperConnectionIdChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _DeveloperPathShortcuts(
          primaryLabel: widget.l10n.agentActionsFormUseDefaultConfigBinPath,
          onPrimaryPressed: saving || !widget.provider.canSaveAction ? null : _applyDefaultDeveloperData7ConfigBinPath,
          secondaryLabel: widget.l10n.agentActionsFormUseDefaultConfigRootPath,
          onSecondaryPressed: saving || !widget.provider.canSaveAction
              ? null
              : _applyDefaultDeveloperData7ConfigRootPath,
        ),
        ..._buildDeveloperConfigPathHints(),
        ..._buildDeveloperResolvedConfigHints(),
        if (widget.provider.developerConnections.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: widget.l10n.agentActionsFormConnectionSearch,
            helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
            helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
            controller: _developerConnectionSearchController,
            enabled: !saving && widget.provider.canSaveAction,
            onChanged: (value) {
              setState(() {
                _developerConnectionSearchQuery = value;
              });
            },
            textInputAction: TextInputAction.search,
          ),
          if (_developerConnectionFilterHasNoMatches) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.l10n.agentActionsFormConnectionFilterEmpty,
              style: context.bodyMuted,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<String>(
          label: widget.l10n.agentActionsFormConnectionSelector,
          helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
          helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
          value:
              _developerConnectionsForSelector().any(
                (option) => option.id == _connectionIdController.text.trim(),
              )
              ? _connectionIdController.text.trim()
              : null,
          items: _developerConnectionsForSelector()
              .map(
                (option) => ComboBoxItem<String>(
                  value: option.id,
                  child: Text(option.label),
                ),
              )
              .toList(growable: false),
          onChanged: saving || !widget.provider.canSaveAction ? null : _applyDeveloperConnectionSelection,
          placeholder: Text(widget.l10n.agentActionsFormConnectionSelectorPlaceholder),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormConnectionLabel,
          helpTitle: widget.l10n.agentActionsHelpDeveloperTitle,
          helpMessage: widget.l10n.agentActionsHelpDeveloperMessage,
          controller: _connectionLabelController,
          enabled: false,
          readOnly: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            unawaited(_save());
          },
        ),
      ],
    };
  }

  List<Widget> _buildPowerShellDraftFields(bool saving) {
    final enabled = !saving && widget.provider.canSaveAction;
    final isEditing = _editingActionId != null;
    final modeField = isEditing
        ? AppTextField(
            key: _AgentActionEditorKeys.powerShellModeDropdown,
            label: widget.l10n.agentActionsFormPowerShellMode,
            helpTitle: widget.l10n.agentActionsHelpPowerShellModeTitle,
            helpMessage: widget.l10n.agentActionsHelpPowerShellModeMessage,
            controller: _powerShellModeDisplayController,
            enabled: !saving,
            readOnly: true,
            textInputAction: TextInputAction.next,
          )
        : AppDropdown<_PowerShellDraftMode>(
            key: _AgentActionEditorKeys.powerShellModeDropdown,
            label: widget.l10n.agentActionsFormPowerShellMode,
            helpTitle: widget.l10n.agentActionsHelpPowerShellModeTitle,
            helpMessage: widget.l10n.agentActionsHelpPowerShellModeMessage,
            value: _powerShellMode,
            items: _PowerShellDraftMode.values
                .map(
                  (mode) {
                    final unavailable = _isPowerShellModeUnavailable(mode);
                    final label = _powerShellModeLabel(mode);
                    return ComboBoxItem<_PowerShellDraftMode>(
                      value: mode,
                      enabled: !unavailable,
                      child: Text(
                        unavailable ? '$label (${widget.l10n.agentActionsRiskRunnerUnavailable})' : label,
                      ),
                    );
                  },
                )
                .toList(growable: false),
            onChanged: enabled
                ? (value) {
                    if (value == null || value == _powerShellMode || _isPowerShellModeUnavailable(value)) {
                      return;
                    }
                    setState(() {
                      _setPowerShellMode(value);
                    });
                  }
                : null,
          );
    final executableField = AppDropdown<_PowerShellExecutable>(
      key: _AgentActionEditorKeys.powerShellExecutableDropdown,
      label: widget.l10n.agentActionsFormPowerShellExecutable,
      helpTitle: widget.l10n.agentActionsHelpPowerShellExecutableTitle,
      helpMessage: widget.l10n.agentActionsHelpPowerShellExecutableMessage,
      value: _powerShellExecutable,
      items: _PowerShellExecutable.values
          .map(
            (executable) => ComboBoxItem<_PowerShellExecutable>(
              value: executable,
              child: Text(_powerShellExecutableLabel(executable)),
            ),
          )
          .toList(growable: false),
      onChanged: enabled
          ? (value) {
              if (value == null || value == _powerShellExecutable) {
                return;
              }
              setState(() {
                _powerShellExecutable = value;
              });
            }
          : null,
    );

    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: modeField),
          const SizedBox(width: AppSpacing.md),
          SizedBox(width: 240, child: executableField),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_powerShellMode == _PowerShellDraftMode.inline) ...[
        AppTextField(
          label: widget.l10n.agentActionsFormPowerShellCommand,
          helpTitle: widget.l10n.agentActionsHelpPowerShellCommandTitle,
          helpMessage: widget.l10n.agentActionsHelpPowerShellCommandMessage,
          controller: _commandController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
      ] else ...[
        AppTextField(
          label: widget.l10n.agentActionsFormPowerShellScriptPath,
          helpTitle: widget.l10n.agentActionsHelpPowerShellScriptTitle,
          helpMessage: widget.l10n.agentActionsHelpPowerShellScriptMessage,
          controller: _scriptPathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          suffixIcon: _PathPickerButton(
            tooltip: widget.l10n.agentActionsFormBrowsePowerShellScriptPath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? _pickPowerShellScriptPath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: widget.l10n.agentActionsFormArguments,
          helpTitle: widget.l10n.agentActionsHelpArgumentsTitle,
          helpMessage: widget.l10n.agentActionsHelpArgumentsMessage,
          controller: _executableArgumentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: widget.l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      AppTextField(
        label: widget.l10n.agentActionsFormWorkingDirectory,
        helpTitle: widget.l10n.agentActionsHelpWorkingDirectoryTitle,
        helpMessage: widget.l10n.agentActionsHelpWorkingDirectoryMessage,
        controller: _workingDirectoryController,
        enabled: enabled,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          unawaited(_save());
        },
      ),
    ];
  }

  String _powerShellModeLabel(_PowerShellDraftMode mode) {
    return switch (mode) {
      _PowerShellDraftMode.inline => widget.l10n.agentActionsFormPowerShellModeCommand,
      _PowerShellDraftMode.script => widget.l10n.agentActionsFormPowerShellModeScript,
    };
  }

  String _powerShellExecutableLabel(_PowerShellExecutable executable) {
    return switch (executable) {
      _PowerShellExecutable.windowsPowerShell => widget.l10n.agentActionsFormPowerShellExecutableWindows,
      _PowerShellExecutable.powerShell7 => widget.l10n.agentActionsFormPowerShellExecutablePwsh,
    };
  }

  List<Widget> _buildDeveloperBinaryPathHints() {
    final hints = <_DeveloperHintData>[];
    final executorPath = _executorPathController.text.trim();
    if (executorPath.isNotEmpty) {
      final normalizedExecutorPath = _normalizePathForComparison(executorPath);
      if (!_endsWithFileName(normalizedExecutorPath, 'executor.exe')) {
        hints.add(
          _DeveloperHintData.warning(
            widget.l10n.agentActionsFormExecutorPathHintExpectedFileName,
          ),
        );
      } else if (normalizedExecutorPath == _normalizePathForComparison(_defaultDeveloperExecutorPath)) {
        hints.add(
          _DeveloperHintData.info(
            widget.l10n.agentActionsFormExecutorPathHintDefault,
          ),
        );
      }
      hints.addAll(
        _buildDeveloperFileInspectionHints(
          path: executorPath,
          missingMessage: widget.l10n.agentActionsFormExecutorPathHintMissing,
          directoryMessage: widget.l10n.agentActionsFormExecutorPathHintDirectory,
        ),
      );
    }

    final projectPath = _projectPathController.text.trim();
    if (projectPath.isNotEmpty) {
      if (!_normalizePathForComparison(projectPath).endsWith('.7proj')) {
        hints.add(
          _DeveloperHintData.warning(
            widget.l10n.agentActionsFormProjectPathHintExpectedExtension,
          ),
        );
      }
      hints.addAll(
        _buildDeveloperFileInspectionHints(
          path: projectPath,
          missingMessage: widget.l10n.agentActionsFormProjectPathHintMissing,
          directoryMessage: widget.l10n.agentActionsFormProjectPathHintDirectory,
        ),
      );
    }

    if (hints.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(hints: hints),
    ];
  }

  List<Widget> _buildDeveloperConfigPathHints() {
    final configPath = _data7ConfigPathController.text.trim();
    if (configPath.isEmpty) {
      return const <Widget>[];
    }

    final normalizedConfigPath = _normalizePathForComparison(configPath);
    final hints = <_DeveloperHintData>[];
    if (!_endsWithFileName(normalizedConfigPath, 'data7.config')) {
      hints.add(
        _DeveloperHintData.warning(
          widget.l10n.agentActionsFormData7ConfigPathHintExpectedFileName,
        ),
      );
    } else if (normalizedConfigPath == _normalizePathForComparison(_defaultDeveloperConfigBinPath)) {
      hints.add(
        _DeveloperHintData.info(
          widget.l10n.agentActionsFormData7ConfigPathHintDefaultBin,
        ),
      );
    } else if (normalizedConfigPath == _normalizePathForComparison(_defaultDeveloperConfigRootPath)) {
      hints.add(
        _DeveloperHintData.info(
          widget.l10n.agentActionsFormData7ConfigPathHintDefaultRoot,
        ),
      );
    }
    hints.addAll(
      _buildDeveloperFileInspectionHints(
        path: configPath,
        missingMessage: widget.l10n.agentActionsFormData7ConfigPathHintMissing,
        directoryMessage: widget.l10n.agentActionsFormData7ConfigPathHintDirectory,
      ),
    );

    if (hints.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(hints: hints),
    ];
  }

  List<Widget> _buildDeveloperResolvedConfigHints() {
    final resolvedPath = widget.provider.resolvedDeveloperData7ConfigPath?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return const <Widget>[];
    }

    final typedPath = _data7ConfigPathController.text.trim();
    final normalizedResolvedPath = _normalizePathForComparison(resolvedPath);
    final normalizedTypedPath = _normalizePathForComparison(typedPath);
    final message = normalizedTypedPath.isNotEmpty && normalizedResolvedPath != normalizedTypedPath
        ? widget.l10n.agentActionsFormLoadedConfigPath(resolvedPath)
        : widget.l10n.agentActionsFormResolvedConfigPath(resolvedPath);

    return <Widget>[
      const SizedBox(height: AppSpacing.xs),
      _DeveloperHintsWrap(
        hints: <_DeveloperHintData>[
          _DeveloperHintData.info(message),
        ],
      ),
    ];
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
              ? _AgentActionsPageKeys.developerConnectionMissingInfoBar
              : _AgentActionsPageKeys.developerConnectionUnknownInfoBar,
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
          key: _AgentActionsPageKeys.developerConnectionChangedInfoBar,
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

  Map<String, Object?>? _parseComObjectArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }

      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    }
  }

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

  List<String> _parseStructuredArguments(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
  }

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
      case _PowerShellDraftMode.inline:
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
      case _PowerShellDraftMode.script:
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
          interpreterPath: _powerShellExecutable == _PowerShellExecutable.powerShell7
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
      _AgentActionDraftKind.commandLine => widget.l10n.agentActionsFormCreateTitle,
      _AgentActionDraftKind.executable => widget.l10n.agentActionsFormCreateExecutableTitle,
      _AgentActionDraftKind.script => widget.l10n.agentActionsFormCreateScriptTitle,
      _AgentActionDraftKind.jar => widget.l10n.agentActionsFormCreateJarTitle,
      _AgentActionDraftKind.email => widget.l10n.agentActionsFormCreateEmailTitle,
      _AgentActionDraftKind.comObject => widget.l10n.agentActionsFormCreateComObjectTitle,
      _AgentActionDraftKind.developer => widget.l10n.agentActionsFormCreateDeveloperTitle,
      _AgentActionDraftKind.powerShell => widget.l10n.agentActionsFormCreatePowerShellTitle,
    };
  }

  String _editTitle() {
    return switch (_draftKind) {
      _AgentActionDraftKind.commandLine => widget.l10n.agentActionsFormEditTitle,
      _AgentActionDraftKind.executable => widget.l10n.agentActionsFormEditExecutableTitle,
      _AgentActionDraftKind.script => widget.l10n.agentActionsFormEditScriptTitle,
      _AgentActionDraftKind.jar => widget.l10n.agentActionsFormEditJarTitle,
      _AgentActionDraftKind.email => widget.l10n.agentActionsFormEditEmailTitle,
      _AgentActionDraftKind.comObject => widget.l10n.agentActionsFormEditComObjectTitle,
      _AgentActionDraftKind.developer => widget.l10n.agentActionsFormEditDeveloperTitle,
      _AgentActionDraftKind.powerShell => widget.l10n.agentActionsFormEditPowerShellTitle,
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

  String _normalizePathForComparison(String path) {
    return path.trim().replaceAll('/', r'\').toLowerCase();
  }

  bool _endsWithFileName(String normalizedPath, String fileName) {
    final expectedSuffix = r'\' + fileName.toLowerCase();
    return normalizedPath.endsWith(expectedSuffix) || normalizedPath == fileName.toLowerCase();
  }

  List<_DeveloperHintData> _buildDeveloperFileInspectionHints({
    required String path,
    required String missingMessage,
    required String directoryMessage,
  }) {
    try {
      final entityType = FileSystemEntity.typeSync(path);
      return switch (entityType) {
        FileSystemEntityType.notFound => <_DeveloperHintData>[
          _DeveloperHintData.warning(missingMessage),
        ],
        FileSystemEntityType.directory => <_DeveloperHintData>[
          _DeveloperHintData.warning(directoryMessage),
        ],
        _ => const <_DeveloperHintData>[],
      };
    } on FileSystemException {
      return <_DeveloperHintData>[
        _DeveloperHintData.warning(
          widget.l10n.agentActionsFormPathHintInspectionFailed,
        ),
      ];
    }
  }
}

class _HelpCheckboxLabel extends StatelessWidget {
  const _HelpCheckboxLabel({
    required this.label,
    required this.helpTitle,
    required this.helpMessage,
  });

  final String label;
  final String helpTitle;
  final String helpMessage;

  String get _helpKeyToken {
    var token = label.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    while (token.startsWith('_')) {
      token = token.substring(1);
    }
    while (token.endsWith('_')) {
      token = token.substring(0, token.length - 1);
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label),
        AppHelpButton(
          key: ValueKey<String>('app_help_button_$_helpKeyToken'),
          title: helpTitle,
          message: helpMessage,
          semanticLabel: '$label. $helpTitle',
        ),
      ],
    );
  }
}
