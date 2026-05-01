import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' show max, min;

import 'package:file_picker/file_picker.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_details_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_data_grid.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

part 'client_token_section_dialog_shell.dart';
part 'client_token_section_widgets.dart';

const _tokenClientFilterKey = 'client_token_list_client_filter';
const _tokenStatusFilterKey = 'client_token_list_status_filter';
const _tokenSortFilterKey = 'client_token_list_sort_filter';
const _tokenAutoRefreshAfterCreateKey = 'client_token_auto_refresh_after_create';

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
  Timer? _clientFilterDebounceTimer;
  final ValueNotifier<int> _createTokenDialogRevision = ValueNotifier<int>(0);
  final FocusNode _createTokenDialogAgentFocusNode = FocusNode();
  bool _isCreateTokenDialogOpen = false;

  bool _allTables = false;
  bool _allViews = false;
  bool _allPermissions = false;
  ClientTokenStatusFilter _tokenStatusFilter = ClientTokenStatusFilter.all;
  ClientTokenSortOption _tokenSortOption = ClientTokenSortOption.newest;
  bool _autoRefreshAfterCreate = true;
  String _formError = '';
  String? _editingTokenId;
  int? _editingTokenVersion;

  @override
  void initState() {
    super.initState();
    _initializeTokenListState();
  }

  Future<void> _initializeTokenListState() async {
    await _restoreTokenListPreferences();
    if (!mounted) {
      return;
    }
    final provider = context.read<ClientTokenProvider>();
    if (!provider.hasLoaded) {
      await provider.loadTokens(silent: true, query: _buildListQuery());
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

  // Merges [incoming] into [_rules]: deduplicates within the batch, then
  // replaces existing rules with the same resource+type or appends new ones.
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

    // Edit always returns exactly one draft — replace the edited entry.
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
    if (!mounted || _isImportingRules) return;
    final l10n = AppLocalizations.of(context)!;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
    } on Exception {
      return;
    }

    if (picked == null || picked.files.isEmpty) return;
    final filePath = picked.files.single.path;
    if (filePath == null) return;

    _setImportingRules(true);

    try {
      final file = File(filePath);
      final size = await file.length();
      if (!mounted) return;

      if (size == 0) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorEmpty,
        );
        return;
      }
      if (size > maxRuleImportFileSizeBytes) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorFileTooLarge,
        );
        return;
      }

      final content = await file.readAsString();
      if (!mounted) return;

      final result = parseTokenRulesStrict(content);

      if (result.drafts.isEmpty) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorEmpty,
        );
        return;
      }

      if (result.hasErrors) {
        final firstError = result.errors.first;
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorInvalidFormat(firstError.line, firstError.content),
        );
        return;
      }

      _mergeRules(result.drafts);
      _notifyCreateTokenDialogChanged();

      if (mounted) {
        final countAdded = result.drafts.length;
        SettingsFeedback.showSuccess(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesSuccess(countAdded),
        );
      }
    } on FormatException catch (e) {
      developer.log('Rule import encoding error', name: 'client_token_section', error: e);
      if (mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorEmpty,
        );
      }
    } on Exception catch (e) {
      developer.log('Failed to import rules', name: 'client_token_section', error: e);
      if (mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorEmpty,
        );
      }
    } finally {
      if (mounted) _setImportingRules(false);
    }
  }

  Future<void> _handleExportRules() async {
    if (_rules.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    final lines = _rules
        .map((rule) {
          final perms = [
            if (rule.canRead) 'read',
            if (rule.canUpdate) 'update',
            if (rule.canDelete) 'delete',
          ].join(',');
          return '${rule.resource};${rule.resourceType.name};${rule.effect.name};$perms';
        })
        .join('\n');

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
      await File(savePath).writeAsString(lines);
    } on Exception catch (e) {
      developer.log(
        'Failed to export rules',
        name: 'client_token_section',
        error: e,
      );
    }
  }

  Future<void> _openCreateTokenModal([ClientTokenSummary? baseToken]) async {
    if (!mounted) {
      return;
    }
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
              ),
            )
            .toList() ??
        <ClientTokenRuleDraft>[];

    setState(() {
      _formError = '';
      _editingTokenId = baseToken?.id;
      _editingTokenVersion = baseToken?.version;
      _nameController.text = baseToken?.name ?? '';
      _clientIdController.text = baseToken?.clientId ?? _generateClientId();
      _agentIdController.text = baseToken?.agentId ?? '';
      _payloadController.text = baseToken?.payload.isEmpty ?? true ? '' : jsonEncode(baseToken!.payload);
      _rules
        ..clear()
        ..addAll(initialRules);
      _allTables = baseToken?.allTables ?? false;
      _allViews = baseToken?.allViews ?? false;
      _allPermissions = baseToken?.allPermissions ?? false;
    });
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    _isCreateTokenDialogOpen = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Dismiss create token dialog',
        barrierColor: Colors.black.withValues(
          alpha: _createTokenBarrierOpacity,
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
              final availableWidth = mediaQuery.size.width - (_createTokenDialogHorizontalMargin * 2);
              final dialogWidth = availableWidth.clamp(
                420.0,
                _createTokenDialogMaxWidth,
              );
              final factorHeight = availableHeight * _createTokenDialogHeightFactor;
              final minPreferredOuter = min(
                _createTokenDialogMinPreferredOuterHeight,
                availableHeight,
              );
              final dialogOuterMaxHeight = max(factorHeight, minPreferredOuter);
              final isCompact = dialogWidth < _createTokenDialogCompactWidthBreakpoint;
              final theme = FluentTheme.of(dialogContext);

              return ChangeNotifierProvider<ClientTokenProvider>.value(
                value: provider,
                child: _CreateTokenDialogShell(
                  navigatorContext: dialogContext,
                  agentFocusNode: _createTokenDialogAgentFocusNode,
                  dialogWidth: dialogWidth,
                  dialogOuterMaxHeight: dialogOuterMaxHeight,
                  theme: theme,
                  isEditingToken: isEditingToken,
                  body: (context, tokenProvider) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _CreateTokenDialogContent(
                            isCompact: isCompact,
                            agentFocusNode: _createTokenDialogAgentFocusNode,
                            nameController: _nameController,
                            clientIdController: _clientIdController,
                            agentIdController: _agentIdController,
                            payloadController: _payloadController,
                            rules: _rules,
                            allTables: _allTables,
                            allViews: _allViews,
                            allPermissions: _allPermissions,
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
                            onToggleAllPermissions: (value) {
                              _allPermissions = value;
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
                        _CreateTokenDialogFooter(
                          isCreating: tokenProvider.isCreating,
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
                Tween(begin: _createTokenScaleStart, end: 1),
              ),
              child: child,
            ),
          );
        },
      );
    } finally {
      _isCreateTokenDialogOpen = false;
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

    final rules = _buildRules();
    if (!_allPermissions && rules.isEmpty) {
      _formError = AppLocalizations.of(context)!.ctErrorRuleOrAllPermissionsRequired;
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
      allPermissions: _allPermissions,
      rules: rules,
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
        _clearTokenDraftForm();
        navigator.pop();
      }
    }
  }

  void _clearTokenDraftForm() {
    _editingTokenId = null;
    _editingTokenVersion = null;
    _clientIdController.text = _generateClientId();
    _agentIdController.clear();
    _payloadController.clear();
    _rules.clear();
    _allTables = false;
    _allViews = false;
    _allPermissions = false;
  }

  Map<String, dynamic>? _parsePayload() {
    final (:payload, :error) = parseClientTokenPayloadJson(_payloadController.text);
    if (error == null) {
      return payload;
    }
    _formError = switch (error) {
      ClientTokenPayloadParseError.invalidJson => AppLocalizations.of(context)!.ctErrorPayloadInvalidJson,
      ClientTokenPayloadParseError.notAnObject => AppLocalizations.of(context)!.ctErrorPayloadMustBeJsonObject,
    };
    _notifyCreateTokenDialogChanged();
    return null;
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
    if (!getIt.isRegistered<IAppSettingsStore>()) {
      return;
    }
    final prefs = getIt<IAppSettingsStore>();
    try {
      final clientFilter = prefs.getString(_tokenClientFilterKey) ?? '';
      final statusFilter = _statusFilterFromStorage(
        prefs.getString(_tokenStatusFilterKey),
      );
      final sortFilter = _sortFilterFromStorage(
        prefs.getString(_tokenSortFilterKey),
      );
      final autoRefreshAfterCreate = prefs.getBool(_tokenAutoRefreshAfterCreateKey) ?? true;
      if (!mounted) {
        return;
      }
      setState(() {
        _listClientFilterController.text = clientFilter;
        _tokenStatusFilter = statusFilter;
        _tokenSortOption = sortFilter;
        _autoRefreshAfterCreate = autoRefreshAfterCreate;
      });
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to restore client token preferences',
        name: 'client_token_section',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveTokenListPreferences() async {
    if (!getIt.isRegistered<IAppSettingsStore>()) {
      return;
    }
    final prefs = getIt<IAppSettingsStore>();
    try {
      await prefs.setString(
        _tokenClientFilterKey,
        _listClientFilterController.text.trim(),
      );
      await prefs.setString(
        _tokenStatusFilterKey,
        _statusFilterToStorage(_tokenStatusFilter),
      );
      await prefs.setString(
        _tokenSortFilterKey,
        _sortFilterToStorage(_tokenSortOption),
      );
      await prefs.setBool(
        _tokenAutoRefreshAfterCreateKey,
        _autoRefreshAfterCreate,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to save client token preferences',
        name: 'client_token_section',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _statusFilterToStorage(ClientTokenStatusFilter value) {
    return switch (value) {
      ClientTokenStatusFilter.all => 'all',
      ClientTokenStatusFilter.active => 'active',
      ClientTokenStatusFilter.revoked => 'revoked',
    };
  }

  ClientTokenStatusFilter _statusFilterFromStorage(String? value) {
    return switch (value) {
      'active' => ClientTokenStatusFilter.active,
      'revoked' => ClientTokenStatusFilter.revoked,
      _ => ClientTokenStatusFilter.all,
    };
  }

  String _sortFilterToStorage(ClientTokenSortOption value) {
    return switch (value) {
      ClientTokenSortOption.newest => 'newest',
      ClientTokenSortOption.oldest => 'oldest',
      ClientTokenSortOption.clientAsc => 'client_asc',
      ClientTokenSortOption.clientDesc => 'client_desc',
    };
  }

  ClientTokenSortOption _sortFilterFromStorage(String? value) {
    return switch (value) {
      'oldest' => ClientTokenSortOption.oldest,
      'client_asc' => ClientTokenSortOption.clientAsc,
      'client_desc' => ClientTokenSortOption.clientDesc,
      _ => ClientTokenSortOption.newest,
    };
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
                    onPressed: _openCreateTokenModal,
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
              Row(
                children: [
                  AppButton(
                    label: l10n.ctButtonRefreshList,
                    icon: FluentIcons.refresh,
                    isPrimary: false,
                    isLoading: provider.isLoading,
                    onPressed: () => provider.loadTokens(query: _buildListQuery()),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppButton(
                    label: _autoRefreshAfterCreate ? l10n.ctButtonAutoRefreshOn : l10n.ctButtonAutoRefreshOff,
                    icon: _autoRefreshAfterCreate ? FluentIcons.sync : FluentIcons.pause,
                    isPrimary: false,
                    onPressed: () {
                      setState(() {
                        _autoRefreshAfterCreate = !_autoRefreshAfterCreate;
                      });
                      _saveTokenListPreferences();
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SettingsSectionTitle(
                title: l10n.ctSectionRegisteredTokens,
              ),
              const SizedBox(height: AppSpacing.sm),
              _TokenListFilters(
                clientFilterController: _listClientFilterController,
                tokenStatusFilter: _tokenStatusFilter,
                tokenSortOption: _tokenSortOption,
                onClientFilterChanged: _handleClientFilterChanged,
                statusLabelBuilder: _statusFilterLabel,
                sortLabelBuilder: _sortFilterLabel,
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
              ),
              const SizedBox(height: AppSpacing.sm),
              if (listedTokens.isEmpty && !provider.isLoading)
                Text(
                  _hasActiveFilters() ? l10n.ctMsgNoTokenMatchFilter : l10n.ctMsgNoTokenFound,
                ),
              if (listedTokens.isNotEmpty)
                SizedBox(
                  height: 440,
                  child: _TokenSummaryGrid(
                    tokens: listedTokens,
                    scrollController: widget.scrollController,
                    isRevokingToken: provider.isRevokingToken,
                    isDeletingToken: provider.isDeletingToken,
                    onViewDetails: (token) => showClientTokenDetailsDialog(
                      context: context,
                      token: token,
                    ),
                    onCopyClientToken: (token) {
                      final tokenValue = token.tokenValue;
                      if (tokenValue == null || tokenValue.trim().isEmpty) {
                        displayInfoBar(
                          context,
                          builder: (context, close) => InfoBar(
                            title: Text(
                              l10n.ctInfoClientTokenUnavailable,
                            ),
                            severity: InfoBarSeverity.warning,
                          ),
                        );
                        return;
                      }

                      Clipboard.setData(ClipboardData(text: tokenValue));
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
                    onEdit: _openCreateTokenModal,
                    onRevoke: (token) {
                      _handleRevoke(context, provider, token);
                    },
                    onDelete: (token) {
                      _handleDelete(context, provider, token);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
