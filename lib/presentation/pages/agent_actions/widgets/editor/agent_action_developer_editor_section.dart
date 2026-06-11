import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_developer_hints.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_draft_field_groups.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_file_picker.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionDeveloperEditorSection extends StatefulWidget {
  const AgentActionDeveloperEditorSection({
    required this.provider,
    required this.l10n,
    required this.draft,
    required this.definition,
    required this.enabled,
    required this.filePicker,
    required this.onSave,
    required this.onValidationMessageChanged,
    required this.onReloadConnections,
    this.showInlineFeedback = true,
    this.onDialogWarning,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionDraft draft;
  final AgentActionDefinition? definition;
  final bool enabled;
  final AgentActionFilePicker filePicker;
  final VoidCallback onSave;
  final ValueChanged<String?> onValidationMessageChanged;
  final Future<void> Function({
    required AgentActionPathPolicy pathPolicy,
    String? selectedConnectionId,
  })
  onReloadConnections;
  final bool showInlineFeedback;
  final void Function(AgentActionEditorDialogWarning warning)? onDialogWarning;

  @override
  State<AgentActionDeveloperEditorSection> createState() => AgentActionDeveloperEditorSectionState();
}

class AgentActionDeveloperEditorSectionState extends State<AgentActionDeveloperEditorSection> {
  static const String _defaultDeveloperExecutorPath = r'C:\Data7\bin\Executor.exe';
  static const String _defaultDeveloperConfigBinPath = r'C:\Data7\bin\Data7.Config';
  static const String _defaultDeveloperConfigRootPath = r'C:\Data7\Data7.Config';
  static const Duration _configPathReloadDebounce = Duration(milliseconds: 500);

  Timer? _configPathReloadTimer;

  AgentActionDraft get _draft => widget.draft;

  static bool isReloadableData7ConfigPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    return AgentActionDraftParsers.endsWithFileName(
      AgentActionDraftParsers.normalizePathForComparison(trimmed),
      'data7.config',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduleInitialConnectionReloadIfNeeded();
      if (!widget.showInlineFeedback && widget.onDialogWarning != null) {
        _publishConnectionChangedWarningIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _cancelConfigPathReloadDebounce();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) => _buildFields(context),
    );
  }

  void _publishConnectionChangedWarningIfNeeded() {
    if (widget.showInlineFeedback || widget.onDialogWarning == null) {
      return;
    }

    final warning = _resolveConnectionStatusWarning();
    if (warning != null && warning.key.startsWith('developer_connection_changed:')) {
      widget.onDialogWarning!(warning);
    }
  }

  AgentActionEditorDialogWarning? _resolveConnectionStatusWarning() {
    return AgentActionDeveloperEditorSectionState.resolveConnectionStatusWarning(
      definition: widget.definition,
      draft: _draft,
      provider: widget.provider,
      l10n: widget.l10n,
    );
  }

  static AgentActionEditorDialogWarning? resolveConnectionStatusWarning({
    required AgentActionDefinition? definition,
    required AgentActionDraft draft,
    required AgentActionsProvider provider,
    required AppLocalizations l10n,
  }) {
    if (definition == null || definition.config is! DeveloperActionConfig) {
      return null;
    }
    if (draft.draftType != AgentActionType.developer) {
      return null;
    }
    if (provider.isLoadingDeveloperConnections) {
      return null;
    }

    final config = definition.config as DeveloperActionConfig;
    final selectedConnectionId = draft.developer.connectionId.text.trim();
    if (selectedConnectionId.isEmpty) {
      return null;
    }

    final selectedOption = provider.developerConnections
        .where((option) => option.id == selectedConnectionId)
        .firstOrNull;

    final savedConnectionId = config.connectionId.trim();
    final isSavedConnectionMissing = selectedConnectionId == savedConnectionId;
    if (selectedOption == null && (isSavedConnectionMissing || provider.developerConnections.isNotEmpty)) {
      return AgentActionEditorDialogWarning(
        key: isSavedConnectionMissing
            ? 'developer_connection_missing:$selectedConnectionId'
            : 'developer_connection_unknown:$selectedConnectionId',
        title: isSavedConnectionMissing
            ? l10n.agentActionsFormConnectionMissingTitle
            : l10n.agentActionsFormConnectionUnknownTitle,
        message: isSavedConnectionMissing
            ? l10n.agentActionsFormConnectionMissingMessage
            : l10n.agentActionsFormConnectionUnknownMessage,
      );
    }

    final savedSnapshotHash = config.connectionSnapshotHash?.trim();
    if (selectedOption != null &&
        savedSnapshotHash != null &&
        savedSnapshotHash.isNotEmpty &&
        savedSnapshotHash != selectedOption.snapshotHash) {
      return AgentActionEditorDialogWarning(
        key: 'developer_connection_changed:$selectedConnectionId',
        title: l10n.agentActionsFormConnectionChangedTitle,
        message: l10n.agentActionsFormConnectionChangedMessage,
      );
    }

    return null;
  }

  Widget _buildFields(BuildContext context) {
    return AgentActionDeveloperFields(
      l10n: widget.l10n,
      enabled: widget.enabled,
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
      showInlineFeedback: widget.showInlineFeedback,
      callbacks: AgentActionDeveloperFieldsCallbacks(
        onBinaryPathChanged: _handleDeveloperBinaryPathChanged,
        onPickExecutorPath: _pickDeveloperExecutorPath,
        onPickProjectPath: _pickDeveloperProjectPath,
        onApplyDefaultExecutorPath: _applyDefaultDeveloperExecutorPath,
        onReloadConnections: () => widget.onReloadConnections(pathPolicy: _draft.pathPolicy()),
        onConfigPathChanged: _handleDeveloperConfigPathChanged,
        onPickConfigPath: _pickDeveloperData7ConfigPath,
        onApplyDefaultConfigBinPath: _applyDefaultDeveloperData7ConfigBinPath,
        onApplyDefaultConfigRootPath: _applyDefaultDeveloperData7ConfigRootPath,
        onConnectionSearchChanged: (value) => setState(() => _draft.developerConnectionSearchQuery = value),
        onConnectionSelected: applyConnectionSelection,
        onSubmitted: widget.onSave,
      ),
    );
  }

  void applyConnectionSelection(String? connectionId) {
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
    if (!widget.showInlineFeedback) {
      return const <Widget>[];
    }

    final warning = _resolveConnectionStatusWarning();
    if (warning == null) {
      return const <Widget>[];
    }

    final infoBarKey = warning.key.startsWith('developer_connection_missing:')
        ? AgentActionEditorKeys.developerConnectionMissingInfoBar
        : warning.key.startsWith('developer_connection_unknown:')
        ? AgentActionEditorKeys.developerConnectionUnknownInfoBar
        : warning.key.startsWith('developer_connection_changed:')
        ? AgentActionEditorKeys.developerConnectionChangedInfoBar
        : null;

    return <Widget>[
      const SizedBox(height: AppSpacing.sm),
      InfoBar(
        key: infoBarKey,
        title: Text(warning.title),
        content: Text(warning.message),
        severity: InfoBarSeverity.warning,
        isLong: true,
      ),
    ];
  }

  void _scheduleInitialConnectionReloadIfNeeded() {
    if (widget.provider.isLoadingDeveloperConnections || widget.provider.developerConnections.isNotEmpty) {
      return;
    }

    final configPath = _draft.developer.data7ConfigPath.text;
    if (!isReloadableData7ConfigPath(configPath)) {
      return;
    }

    unawaited(widget.onReloadConnections(pathPolicy: _draft.pathPolicy()));
  }

  void _cancelConfigPathReloadDebounce() {
    _configPathReloadTimer?.cancel();
    _configPathReloadTimer = null;
  }

  void _scheduleDebouncedConfigPathReload() {
    _cancelConfigPathReloadDebounce();
    _configPathReloadTimer = Timer(_configPathReloadDebounce, () {
      if (!mounted) {
        return;
      }

      unawaited(widget.onReloadConnections(pathPolicy: _draft.pathPolicy()));
    });
  }

  void _handleDeveloperConfigPathChanged(String value) {
    widget.provider.clearDeveloperData7Connections(notify: false);
    setState(() {
      _draft.developer.connectionId.clear();
      _draft.developer.connectionLabel.clear();
      _draft.developerConnectionSearchQuery = '';
      _draft.developer.connectionSearch.clear();
      widget.onValidationMessageChanged(null);
    });

    if (!isReloadableData7ConfigPath(value)) {
      _configPathReloadTimer?.cancel();
      return;
    }

    _scheduleDebouncedConfigPathReload();
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
      widget.onValidationMessageChanged(null);
    });
  }

  Future<void> _pickDeveloperExecutorPath() => _pickAndApply(
    dialogTitle: widget.l10n.agentActionsFormBrowseExecutorPath,
    allowedExtensions: const ['exe'],
    apply: (path) => _draft.developer.executorPath.text = path,
  );

  void _applyDefaultDeveloperExecutorPath() {
    setState(() {
      _draft.developer.executorPath.text = _defaultDeveloperExecutorPath;
      widget.onValidationMessageChanged(null);
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
        await widget.onReloadConnections(pathPolicy: _draft.pathPolicy());
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
    _cancelConfigPathReloadDebounce();
    setState(() {
      _draft.developer.data7ConfigPath.text = path;
      _draft.developer.connectionId.clear();
      _draft.developer.connectionLabel.clear();
      widget.onValidationMessageChanged(null);
    });
    widget.provider.clearDeveloperData7Connections(notify: false);

    await widget.onReloadConnections(pathPolicy: _draft.pathPolicy());
  }

  Future<void> _pickAndApply({
    required String dialogTitle,
    required List<String> allowedExtensions,
    required void Function(String selectedPath) apply,
    Future<void> Function()? onAfter,
  }) async {
    final String? selectedPath;
    try {
      selectedPath = await widget.filePicker.pickSingleFile(
        dialogTitle: dialogTitle,
        allowedExtensions: allowedExtensions,
      );
    } on Exception {
      if (!mounted) {
        return;
      }
      final message = widget.l10n.agentActionsFormBrowseFileError;
      setState(() {
        widget.onValidationMessageChanged(message);
      });
      if (!widget.showInlineFeedback && widget.onDialogWarning != null) {
        widget.onDialogWarning!(
          AgentActionEditorDialogWarning(
            key: 'developer_browse_file_error',
            title: widget.l10n.agentActionsValidationTitle,
            message: message,
          ),
        );
      }
      return;
    }
    if (selectedPath == null || !mounted) {
      return;
    }

    setState(() {
      apply(selectedPath!);
      widget.onValidationMessageChanged(null);
    });

    if (onAfter != null) {
      await onAfter();
    }
  }
}
