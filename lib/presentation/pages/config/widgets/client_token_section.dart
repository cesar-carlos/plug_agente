import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' show max, min;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_content.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_footer.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_shell.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_panel.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_details_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_list_preferences.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_file_service.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class ClientTokenSection extends StatefulWidget {
  const ClientTokenSection({
    this.scrollController,
    super.key,
  });

  final ScrollController? scrollController;

  @override
  State<ClientTokenSection> createState() => _ClientTokenSectionState();
}

class _ClientTokenSectionState extends State<ClientTokenSection> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _agentIdController = TextEditingController();
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _listClientFilterController = TextEditingController();
  final List<ClientTokenRuleDraft> _rules = <ClientTokenRuleDraft>[];
  final ClientTokenRuleFileService _ruleFileService = const ClientTokenRuleFileService();
  late final ClientTokenListPreferences _listPreferences;
  var _listPreferencesInitialized = false;
  Timer? _clientFilterDebounceTimer;
  final ValueNotifier<int> _createTokenDialogRevision = ValueNotifier<int>(0);
  final FocusNode _createTokenDialogAgentFocusNode = FocusNode();
  bool _isCreateTokenDialogOpen = false;

  bool _allTables = false;
  bool _allViews = false;
  bool _globalCanRead = false;
  bool _globalCanUpdate = false;
  bool _globalCanDelete = false;
  bool _globalCanDdl = false;
  ClientTokenStatusFilter _tokenStatusFilter = ClientTokenStatusFilter.all;
  ClientTokenSortOption _tokenSortOption = ClientTokenSortOption.newest;
  bool _autoRefreshAfterCreate = true;
  String _formError = '';
  String? _editingTokenId;
  int? _editingTokenVersion;
  ClientTokenSummary? _editingTokenSnapshot;
  bool _dialogControllerListenersAttached = false;

  bool get _isGlobalScopeMode => _allTables || _allViews;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listPreferencesInitialized) {
      _listPreferencesInitialized = true;
      _listPreferences = ClientTokenListPreferences(
        () => readOptionalPresentationProvider<IAppSettingsStore>(context),
      );
      unawaited(_initializeTokenListState());
    }
  }

  Future<void> _initializeTokenListState() async {
    await _restoreTokenListPreferences();
    if (!mounted) {
      return;
    }
    final provider = context.read<ClientTokenProvider>();
    if (!provider.hasLoaded) {
      await provider.loadTokens(query: _buildListQuery());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientIdController.dispose();
    _agentIdController.dispose();
    _payloadController.dispose();
    _listClientFilterController.dispose();
    _clientFilterDebounceTimer?.cancel();
    _createTokenDialogRevision.dispose();
    _createTokenDialogAgentFocusNode.dispose();
    super.dispose();
  }

  void _notifyCreateTokenDialogChanged() {
    if (_isCreateTokenDialogOpen) {
      _createTokenDialogRevision.value++;
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _attachDialogControllerListeners() {
    if (_dialogControllerListenersAttached) {
      return;
    }
    _nameController.addListener(_notifyCreateTokenDialogChanged);
    _clientIdController.addListener(_notifyCreateTokenDialogChanged);
    _agentIdController.addListener(_notifyCreateTokenDialogChanged);
    _payloadController.addListener(_notifyCreateTokenDialogChanged);
    _dialogControllerListenersAttached = true;
  }

  void _detachDialogControllerListeners() {
    if (!_dialogControllerListenersAttached) {
      return;
    }
    _nameController.removeListener(_notifyCreateTokenDialogChanged);
    _clientIdController.removeListener(_notifyCreateTokenDialogChanged);
    _agentIdController.removeListener(_notifyCreateTokenDialogChanged);
    _payloadController.removeListener(_notifyCreateTokenDialogChanged);
    _dialogControllerListenersAttached = false;
  }

  ClientTokenCreateRequest? _tryBuildDraftRequestFromForm() {
    final (:payload, :error) = parseClientTokenPayloadJson(_payloadController.text);
    if (error != null || payload == null) {
      return null;
    }
    final globalPermissions = _buildGlobalPermissions();
    return ClientTokenCreateRequest(
      clientId: _clientIdController.text.trim(),
      name: _nameController.text.trim(),
      agentId: _agentIdController.text.trim().isEmpty ? null : _agentIdController.text.trim(),
      payload: payload,
      allTables: _allTables,
      allViews: _allViews,
      globalPermissions: globalPermissions,
      rules: _isGlobalScopeMode ? const <ClientTokenRule>[] : _buildRules(),
    );
  }

  bool _hasFormChanges() {
    final snapshot = _editingTokenSnapshot;
    if (snapshot == null) {
      return true;
    }
    final draft = _tryBuildDraftRequestFromForm();
    if (draft == null) {
      return true;
    }
    return draft.changesAuthorizationPolicyFrom(snapshot) || draft.changesMetadataFrom(snapshot);
  }

  bool _hasPolicyChanges() {
    final snapshot = _editingTokenSnapshot;
    if (snapshot == null) {
      return false;
    }
    final draft = _tryBuildDraftRequestFromForm();
    if (draft == null) {
      return false;
    }
    return draft.changesAuthorizationPolicyFrom(snapshot);
  }

  void _mergeRules(List<ClientTokenRuleDraft> incoming) {
    final seen = <String>{};
    final deduped = incoming.reversed
        .where((d) => seen.add('${d.resource.toLowerCase()}:${d.resourceType.name}'))
        .toList()
        .reversed
        .toList();

    for (final draft in deduped) {
      final existingIndex = _rules.indexWhere(
        (r) => r.resource.toLowerCase() == draft.resource.toLowerCase() && r.resourceType == draft.resourceType,
      );
      if (existingIndex >= 0) {
        _rules[existingIndex] = draft;
      } else {
        _rules.add(draft);
      }
    }
  }

  Future<void> _openAddRuleModal() async {
    if (_isGlobalScopeMode) {
      return;
    }
    final result = await showClientTokenRuleDialog(
      context: context,
      existingRules: List.unmodifiable(_rules),
    );
    if (!mounted || result == null) return;

    _mergeRules(result);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyCreateTokenDialogChanged();
    });
  }

  Future<void> _openEditRuleModal(int index) async {
    final result = await showClientTokenRuleDialog(
      context: context,
      initialRule: _rules[index],
      existingRules: List.unmodifiable(_rules),
    );
    if (!mounted || result == null) return;

    _rules[index] = result.first;
    _notifyCreateTokenDialogChanged();
  }

  void _removeRule(int index) {
    _rules.removeAt(index);
    _notifyCreateTokenDialogChanged();
  }

  bool _isImportingRules = false;

  void _setImportingRules(bool value) {
    _isImportingRules = value;
    _notifyCreateTokenDialogChanged();
  }

  Future<void> _handleImportRulesFromSection() async {
    if (!mounted || _isImportingRules || _isGlobalScopeMode) return;
    final l10n = AppLocalizations.of(context)!;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
    } on Exception catch (e, st) {
      developer.log('Rule import picker failed', name: 'client_token_section', error: e, stackTrace: st);
      if (mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorReadFailed,
        );
      }
      return;
    }

    if (picked == null || picked.files.isEmpty) return;
    final filePath = picked.files.single.path;
    if (filePath == null) return;

    _setImportingRules(true);

    try {
      final outcome = await _ruleFileService.importFromFile(filePath);
      if (!mounted) return;

      switch (outcome) {
        case ClientTokenRuleImportEmpty():
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorEmpty,
          );
        case ClientTokenRuleImportTooLarge():
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorFileTooLarge,
          );
        case ClientTokenRuleImportInvalidFormat(:final line, :final content):
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorInvalidFormat(line, content),
          );
        case ClientTokenRuleImportReadFailure(:final error, :final stackTrace):
          developer.log('Failed to import rules', name: 'client_token_section', error: error, stackTrace: stackTrace);
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorEmpty,
          );
        case ClientTokenRuleImportLoaded(:final drafts):
          _mergeRules(drafts);
          _notifyCreateTokenDialogChanged();
          SettingsFeedback.showSuccess(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesSuccess(drafts.length),
          );
      }
    } finally {
      if (mounted) _setImportingRules(false);
    }
  }

  Future<void> _handleExportRules() async {
    if (_rules.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    final tokenName = _nameController.text.trim();
    final defaultFileName = tokenName.isNotEmpty
        ? '${tokenName.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '')}.txt'
        : l10n.ctExportRulesDefaultFileName;

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.ctButtonExportRules,
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (savePath == null) return;
      await _ruleFileService.exportToFile(savePath, _rules);
    } on Exception catch (e, st) {
      developer.log(
        'Failed to export rules',
        name: 'client_token_section',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonExportRules,
          message: l10n.ctExportRulesError,
        );
      }
    }
  }

  Future<void> _openCreateTokenModal([ClientTokenSummary? baseToken]) async {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final isEditingToken = baseToken != null;

    final initialRules =
        baseToken?.rules
            .map(
              (rule) => ClientTokenRuleDraft(
                resource: rule.resource.name,
                resourceType: rule.resource.resourceType,
                effect: rule.effect,
                canRead: rule.permissions.canRead,
                canUpdate: rule.permissions.canUpdate,
                canDelete: rule.permissions.canDelete,
                canDdl: rule.permissions.canDdl,
              ),
            )
            .toList() ??
        <ClientTokenRuleDraft>[];

    setState(() {
      _formError = '';
      _editingTokenId = baseToken?.id;
      _editingTokenVersion = baseToken?.version;
      _editingTokenSnapshot = baseToken;
      _nameController.text = baseToken?.name ?? '';
      _clientIdController.text = baseToken?.clientId ?? _generateClientId();
      _agentIdController.text = baseToken?.agentId ?? '';
      _payloadController.text = baseToken?.payload.isEmpty ?? true ? '' : jsonEncode(baseToken!.payload);
      _rules
        ..clear()
        ..addAll(initialRules);
      _allTables = baseToken?.allTables ?? false;
      _allViews = baseToken?.allViews ?? false;
      _globalCanRead = baseToken?.globalPermissions.canRead ?? false;
      _globalCanUpdate = baseToken?.globalPermissions.canUpdate ?? false;
      _globalCanDelete = baseToken?.globalPermissions.canDelete ?? false;
      _globalCanDdl = baseToken?.globalPermissions.canDdl ?? false;
    });
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();
    provider.clearLastUpdateOutcome();

    _attachDialogControllerListeners();
    _isCreateTokenDialogOpen = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierLabel: l10n.ctDialogDismissCreateToken,
        barrierColor: Colors.black.withValues(
          alpha: createTokenBarrierOpacity,
        ),
        pageBuilder: (_, primaryAnimation, secondaryAnimation) {
          return ValueListenableBuilder<int>(
            valueListenable: _createTokenDialogRevision,
            builder: (dialogContext, revision, child) {
              final mediaQuery = MediaQuery.of(dialogContext);
              final availableHeight =
                  (mediaQuery.size.height - mediaQuery.padding.vertical - mediaQuery.viewInsets.bottom).clamp(
                    0.0,
                    double.infinity,
                  );
              final availableWidth = mediaQuery.size.width - (createTokenDialogHorizontalMargin * 2);
              final dialogWidth = availableWidth.clamp(
                420.0,
                createTokenDialogMaxWidth,
              );
              final factorHeight = availableHeight * createTokenDialogHeightFactor;
              final minPreferredOuter = min(
                createTokenDialogMinPreferredOuterHeight,
                availableHeight,
              );
              final dialogOuterMaxHeight = max(factorHeight, minPreferredOuter);
              final isCompact = dialogWidth < createTokenDialogCompactWidthBreakpoint;
              final theme = FluentTheme.of(dialogContext);

              return ChangeNotifierProvider<ClientTokenProvider>.value(
                value: provider,
                child: ClientTokenCreateDialogShell(
                  navigatorContext: dialogContext,
                  agentFocusNode: _createTokenDialogAgentFocusNode,
                  dialogWidth: dialogWidth,
                  dialogOuterMaxHeight: dialogOuterMaxHeight,
                  theme: theme,
                  isEditingToken: isEditingToken,
                  body: (context, tokenProvider) {
                    final hasChanges = _hasFormChanges();
                    final policyChanged = _hasPolicyChanges();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClientTokenCreateDialogContent(
                            isCompact: isCompact,
                            isEditingToken: isEditingToken,
                            policyChanged: policyChanged,
                            hasFormChanges: hasChanges,
                            agentFocusNode: _createTokenDialogAgentFocusNode,
                            nameController: _nameController,
                            clientIdController: _clientIdController,
                            agentIdController: _agentIdController,
                            payloadController: _payloadController,
                            rules: _rules,
                            allTables: _allTables,
                            allViews: _allViews,
                            globalCanRead: _globalCanRead,
                            globalCanUpdate: _globalCanUpdate,
                            globalCanDelete: _globalCanDelete,
                            globalCanDdl: _globalCanDdl,
                            formError: _formError,
                            providerError: tokenProvider.error,
                            lastCreatedToken: tokenProvider.lastCreatedToken,
                            onToggleAllTables: (value) {
                              _allTables = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onToggleAllViews: (value) {
                              _allViews = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalRead: (value) {
                              _globalCanRead = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalUpdate: (value) {
                              _globalCanUpdate = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalDelete: (value) {
                              _globalCanDelete = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalDdl: (value) {
                              _globalCanDdl = value;
                              _notifyCreateTokenDialogChanged();
                            },
                            onAddRule: _openAddRuleModal,
                            onExportRules: _handleExportRules,
                            onImportRules: _handleImportRulesFromSection,
                            isImportingRules: _isImportingRules,
                            onEditRule: _openEditRuleModal,
                            onDeleteRule: _removeRule,
                            onDismissCreatedToken: tokenProvider.clearLastCreatedToken,
                            onFieldSubmitted: _handleSubmitToken,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ClientTokenCreateDialogFooter(
                          isCreating: tokenProvider.isCreating,
                          canSubmit: hasChanges,
                          submitLabel: isEditingToken
                              ? AppLocalizations.of(dialogContext)!.ctButtonSaveTokenChanges
                              : AppLocalizations.of(dialogContext)!.ctButtonCreateToken,
                          onCancel: () => Navigator.of(dialogContext).pop(),
                          onSubmit: _handleSubmitToken,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
        transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: curved.drive(
                Tween(begin: createTokenScaleStart, end: 1),
              ),
              child: child,
            ),
          );
        },
      );
    } finally {
      _isCreateTokenDialogOpen = false;
      _detachDialogControllerListeners();
    }
  }

  Future<void> _handleSubmitToken() async {
    _formError = '';
    _notifyCreateTokenDialogChanged();

    final navigator = Navigator.of(context, rootNavigator: true);
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    final clientId = _clientIdController.text.trim();

    final payloadResult = _parsePayload();
    if (payloadResult == null) {
      return;
    }

    final globalPermissions = _buildGlobalPermissions();
    final rules = _buildRules();
    if (_isGlobalScopeMode && !globalPermissions.hasAnyPermission) {
      _formError = AppLocalizations.of(context)!.ctErrorGlobalPermissionRequired;
      _notifyCreateTokenDialogChanged();
      return;
    }
    if (!_isGlobalScopeMode && rules.isEmpty) {
      _formError = AppLocalizations.of(context)!.ctErrorRuleOrGlobalPermissionsRequired;
      _notifyCreateTokenDialogChanged();
      return;
    }

    final request = ClientTokenCreateRequest(
      clientId: clientId,
      name: _nameController.text.trim(),
      agentId: _agentIdController.text.trim().isEmpty ? null : _agentIdController.text.trim(),
      payload: payloadResult,
      allTables: _allTables,
      allViews: _allViews,
      globalPermissions: globalPermissions,
      rules: _isGlobalScopeMode ? const <ClientTokenRule>[] : rules,
    );

    final previousOffset = _getCurrentScrollOffset();
    final currentEditingTokenId = _editingTokenId;
    final isSuccess = currentEditingTokenId == null
        ? await provider.createToken(
            request,
            refreshTokens: false,
          )
        : await provider.updateToken(
            currentEditingTokenId,
            request,
            refreshTokens: false,
            expectedVersion: _editingTokenVersion,
          );

    if (isSuccess && mounted) {
      if (_autoRefreshAfterCreate) {
        await _refreshTokensPreservingPosition(previousOffset);
      }
      if (!mounted) return;
      _formError = '';
      _notifyCreateTokenDialogChanged();
      if (provider.error.isEmpty) {
        final outcome = provider.lastUpdateOutcome;
        final rotatedTokenValue = provider.lastCreatedToken;
        _clearTokenDraftForm();
        navigator.pop();
        if (currentEditingTokenId != null) {
          _showEditOutcomeFeedback(
            outcome: outcome,
            rotatedTokenValue: rotatedTokenValue,
          );
        }
      }
    }
  }

  void _showEditOutcomeFeedback({
    required ClientTokenUpdateOutcome? outcome,
    required String? rotatedTokenValue,
  }) {
    if (!mounted || outcome == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    switch (outcome) {
      case ClientTokenUpdateOutcome.unchanged:
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenNoChanges),
            onClose: close,
          ),
        );
        return;
      case ClientTokenUpdateOutcome.metadataOnly:
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenMetadataUpdated),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
        return;
      case ClientTokenUpdateOutcome.rotated:
        if (rotatedTokenValue == null || rotatedTokenValue.isEmpty) {
          return;
        }
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenRotated),
            content: SelectableText(rotatedTokenValue),
            severity: InfoBarSeverity.success,
            onClose: close,
            action: FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rotatedTokenValue));
                close();
              },
              child: Text(l10n.ctButtonCopyToken),
            ),
          ),
        );
        return;
    }
  }

  void _clearTokenDraftForm() {
    _editingTokenId = null;
    _editingTokenVersion = null;
    _editingTokenSnapshot = null;
    _clientIdController.text = _generateClientId();
    _agentIdController.clear();
    _payloadController.clear();
    _rules.clear();
    _allTables = false;
    _allViews = false;
    _globalCanRead = false;
    _globalCanUpdate = false;
    _globalCanDelete = false;
    _globalCanDdl = false;
  }

  Map<String, dynamic>? _parsePayload() {
    final (:payload, :error) = parseClientTokenPayloadJson(_payloadController.text);
    if (error == null) {
      final payloadValidationError = validateClientTokenPayload(payload!);
      if (payloadValidationError == null) {
        return payload;
      }
      _formError = switch (payloadValidationError) {
        ClientTokenPayloadValidationError.databaseMustBeString => AppLocalizations.of(
          context,
        )!.ctErrorPayloadDatabaseMustBeString,
        ClientTokenPayloadValidationError.databaseCannotBeEmpty => AppLocalizations.of(
          context,
        )!.ctErrorPayloadDatabaseCannotBeEmpty,
      };
      _notifyCreateTokenDialogChanged();
      return null;
    }
    _formError = switch (error) {
      ClientTokenPayloadParseError.invalidJson => AppLocalizations.of(context)!.ctErrorPayloadInvalidJson,
      ClientTokenPayloadParseError.notAnObject => AppLocalizations.of(context)!.ctErrorPayloadMustBeJsonObject,
    };
    _notifyCreateTokenDialogChanged();
    return null;
  }

  ClientPermissionSet _buildGlobalPermissions() {
    if (!_isGlobalScopeMode) {
      return ClientPermissionSet.none;
    }

    return ClientPermissionSet(
      canRead: _globalCanRead,
      canUpdate: _globalCanUpdate,
      canDelete: _globalCanDelete,
      canDdl: _globalCanDdl,
    );
  }

  String _generateClientId() {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return 'client_$timestamp';
  }

  List<ClientTokenRule> _buildRules() {
    final rules = <ClientTokenRule>[];
    for (final draft in _rules) {
      if (!draft.hasAnyPermission) {
        continue;
      }
      rules.add(
        ClientTokenRule(
          resource: DatabaseResource(
            resourceType: draft.resourceType,
            name: draft.resource,
          ),
          permissions: ClientPermissionSet(
            canRead: draft.canRead,
            canUpdate: draft.canUpdate,
            canDelete: draft.canDelete,
            canDdl: draft.canDdl,
          ),
          effect: draft.effect,
        ),
      );
    }
    return rules;
  }

  String _statusFilterLabel(ClientTokenStatusFilter value) {
    final l10n = AppLocalizations.of(context)!;
    return switch (value) {
      ClientTokenStatusFilter.all => l10n.ctFilterStatusAll,
      ClientTokenStatusFilter.active => l10n.ctFilterStatusActive,
      ClientTokenStatusFilter.revoked => l10n.ctFilterStatusRevoked,
    };
  }

  String _sortFilterLabel(ClientTokenSortOption value) {
    final l10n = AppLocalizations.of(context)!;
    return switch (value) {
      ClientTokenSortOption.newest => l10n.ctSortNewest,
      ClientTokenSortOption.oldest => l10n.ctSortOldest,
      ClientTokenSortOption.clientAsc => l10n.ctSortClientAsc,
      ClientTokenSortOption.clientDesc => l10n.ctSortClientDesc,
    };
  }

  void _clearTokenFilters() {
    _listClientFilterController.clear();
    setState(() {
      _tokenStatusFilter = ClientTokenStatusFilter.all;
      _tokenSortOption = ClientTokenSortOption.newest;
    });
    _saveTokenListPreferences();
    _reloadTokensForCurrentFilters();
  }

  Future<void> _restoreTokenListPreferences() async {
    final data = _listPreferences.restore();
    if (data == null || !mounted) {
      return;
    }
    setState(() {
      _listClientFilterController.text = data.clientFilter;
      _tokenStatusFilter = data.statusFilter;
      _tokenSortOption = data.sortOption;
      _autoRefreshAfterCreate = data.autoRefreshAfterCreate;
    });
  }

  Future<void> _saveTokenListPreferences() {
    return _listPreferences.save((
      clientFilter: _listClientFilterController.text.trim(),
      statusFilter: _tokenStatusFilter,
      sortOption: _tokenSortOption,
      autoRefreshAfterCreate: _autoRefreshAfterCreate,
    ));
  }

  double? _getCurrentScrollOffset() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return null;
    }
    return controller.offset;
  }

  Future<void> _refreshTokensPreservingPosition(double? previousOffset) async {
    final provider = context.read<ClientTokenProvider>();
    final refreshed = await provider.loadTokens(
      silent: true,
      query: _buildListQuery(),
    );
    if (!refreshed || previousOffset == null || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.scrollController;
      if (controller == null || !controller.hasClients) {
        return;
      }
      final clampedOffset = previousOffset.clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(clampedOffset);
    });
  }

  Future<void> _handleCopyToken(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await provider.getTokenSecret(token.id);
    if (!context.mounted) {
      return;
    }

    result.fold(
      (lookup) {
        final tokenValue = lookup.tokenValue;
        if (!lookup.isAvailable) {
          displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: Text(l10n.ctInfoClientTokenUnavailable),
              severity: InfoBarSeverity.warning,
            ),
          );
          return;
        }

        Clipboard.setData(ClipboardData(text: tokenValue!));
        provider.recordCopiedToken(
          tokenId: token.id,
          clientId: token.clientId,
        );
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctInfoClientTokenCopied),
            severity: InfoBarSeverity.success,
          ),
        );
      },
      (failure) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctInfoClientTokenLoadFailed),
            content: SelectableText(failure.toDisplayMessage()),
            severity: InfoBarSeverity.error,
          ),
        );
      },
    );
  }

  Future<void> _handleRevoke(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: l10n.ctConfirmRevokeTitle,
      message: l10n.ctConfirmRevokeMessage,
      confirmText: l10n.ctButtonRevoke,
    );
    if (!mounted || !confirmed) {
      return;
    }
    await provider.revokeToken(token.id);
    if (!context.mounted) return;
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: provider.error,
        onConfirm: () => provider.clearError(),
      );
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: l10n.ctConfirmDeleteTitle,
      message: l10n.ctConfirmDeleteMessage,
      confirmText: l10n.ctButtonDelete,
    );
    if (!mounted || !confirmed) {
      return;
    }
    await provider.deleteToken(token.id);
    if (!context.mounted) return;
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: provider.error,
        onConfirm: () => provider.clearError(),
      );
    }
  }

  void _handleClientFilterChanged(String _) {
    _clientFilterDebounceTimer?.cancel();
    _clientFilterDebounceTimer = Timer(
      AppConstants.clientTokenDebounceDelay,
      () {
        if (!mounted) {
          return;
        }
        _saveTokenListPreferences();
        _reloadTokensForCurrentFilters();
      },
    );
  }

  ClientTokenListQuery _buildListQuery() {
    return ClientTokenListQuery(
      clientIdContains: _listClientFilterController.text.trim(),
      status: _tokenStatusFilter,
      sort: _tokenSortOption,
    );
  }

  bool _hasActiveFilters() {
    return _listClientFilterController.text.trim().isNotEmpty ||
        _tokenStatusFilter != ClientTokenStatusFilter.all ||
        _tokenSortOption != ClientTokenSortOption.newest;
  }

  Future<void> _reloadTokensForCurrentFilters() async {
    final provider = context.read<ClientTokenProvider>();
    await provider.loadTokens(
      silent: true,
      query: _buildListQuery(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientTokenProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
        final listedTokens = provider.tokens;
        final isInitialLoading = provider.isLoading && !provider.hasLoaded;
        final isListInteractionLocked = provider.isTokenMutationInProgress;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SettingsSectionTitle(
                      title: l10n.ctSectionTitle,
                    ),
                  ),
                  AppButton(
                    label: l10n.ctButtonNewToken,
                    isPrimary: false,
                    icon: FluentIcons.add,
                    onPressed: isListInteractionLocked ? null : _openCreateTokenModal,
                  ),
                ],
              ),
              if (provider.error.isNotEmpty) ...[
                InlineFeedbackCard(
                  severity: InfoBarSeverity.error,
                  title: l10n.modalTitleError,
                  message: provider.error,
                  onDismiss: provider.clearError,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
              ClientTokenListPanel(
                listedTokens: listedTokens,
                isInitialLoading: isInitialLoading,
                isListInteractionLocked: isListInteractionLocked,
                hasLoaded: provider.hasLoaded,
                isLoading: provider.isLoading,
                hasLoadError: provider.error.isNotEmpty,
                hasActiveFilters: _hasActiveFilters(),
                clientFilterController: _listClientFilterController,
                tokenStatusFilter: _tokenStatusFilter,
                tokenSortOption: _tokenSortOption,
                autoRefreshAfterCreate: _autoRefreshAfterCreate,
                statusLabelBuilder: _statusFilterLabel,
                sortLabelBuilder: _sortFilterLabel,
                onClientFilterChanged: _handleClientFilterChanged,
                onStatusChanged: (value) {
                  setState(() {
                    _tokenStatusFilter = value;
                  });
                  _saveTokenListPreferences();
                  _reloadTokensForCurrentFilters();
                },
                onSortChanged: (value) {
                  setState(() {
                    _tokenSortOption = value;
                  });
                  _saveTokenListPreferences();
                  _reloadTokensForCurrentFilters();
                },
                onClearFilters: _clearTokenFilters,
                onRefresh: () => provider.loadTokens(query: _buildListQuery()),
                onToggleAutoRefresh: () {
                  setState(() {
                    _autoRefreshAfterCreate = !_autoRefreshAfterCreate;
                  });
                  _saveTokenListPreferences();
                },
                onRetryLoad: () => provider.loadTokens(query: _buildListQuery()),
                scrollController: widget.scrollController,
                isRevokingToken: provider.isRevokingToken,
                isDeletingToken: provider.isDeletingToken,
                isCopyingTokenSecret: provider.isCopyingTokenSecretFor,
                onViewDetails: (token) => showClientTokenDetailsDialog(
                  context: context,
                  token: token,
                ),
                onCopyClientToken: (token) {
                  unawaited(_handleCopyToken(context, provider, token));
                },
                onEdit: _openCreateTokenModal,
                onRevoke: (token) {
                  _handleRevoke(context, provider, token);
                },
                onDelete: (token) {
                  _handleDelete(context, provider, token);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
