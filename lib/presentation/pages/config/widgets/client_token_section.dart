import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

const _tokenClientFilterKey = 'client_token_list_client_filter';
const _tokenStatusFilterKey = 'client_token_list_status_filter';
const _tokenSortFilterKey = 'client_token_list_sort_filter';
const _tokenAutoRefreshAfterCreateKey =
    'client_token_auto_refresh_after_create';
const _createTokenDialogMaxWidth = 1120.0;
const _createTokenDialogHorizontalMargin = 40.0;
const _createTokenDialogHeightFactor = 0.84;
const _createTokenBarrierOpacity = 0.4;
const _createTokenScaleStart = 0.95;

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
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _agentIdController = TextEditingController();
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _listClientFilterController =
      TextEditingController();
  final List<ClientTokenRuleDraft> _rules = <ClientTokenRuleDraft>[];
  Timer? _clientFilterDebounceTimer;
  final ValueNotifier<int> _createTokenDialogRevision = ValueNotifier<int>(0);
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
    _clientIdController.dispose();
    _agentIdController.dispose();
    _payloadController.dispose();
    _listClientFilterController.dispose();
    _clientFilterDebounceTimer?.cancel();
    _createTokenDialogRevision.dispose();
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

  Future<void> _openAddRuleModal() async {
    final result = await showClientTokenRuleDialog(context: context);
    if (!mounted || result == null) return;

    _rules.add(result);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyCreateTokenDialogChanged();
    });
  }

  Future<void> _openEditRuleModal(int index) async {
    final result = await showClientTokenRuleDialog(
      context: context,
      initialRule: _rules[index],
    );
    if (!mounted || result == null) return;

    _rules[index] = result;
    _notifyCreateTokenDialogChanged();
  }

  void _removeRule(int index) {
    _rules.removeAt(index);
    _notifyCreateTokenDialogChanged();
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
      _clientIdController.text = baseToken?.clientId ?? _generateClientId();
      _agentIdController.text = baseToken?.agentId ?? '';
      _payloadController.text = baseToken?.payload.isEmpty ?? true
          ? ''
          : jsonEncode(baseToken!.payload);
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
        barrierDismissible: true,
        barrierLabel: 'Dismiss create token dialog',
        barrierColor: Colors.black.withValues(
          alpha: _createTokenBarrierOpacity,
        ),
        pageBuilder: (_, primaryAnimation, secondaryAnimation) {
          return ValueListenableBuilder<int>(
            valueListenable: _createTokenDialogRevision,
            builder: (dialogContext, revision, child) {
              final screenSize = MediaQuery.sizeOf(dialogContext);
              final availableWidth =
                  screenSize.width - (_createTokenDialogHorizontalMargin * 2);
              final dialogWidth = availableWidth.clamp(
                420.0,
                _createTokenDialogMaxWidth,
              );
              final dialogMaxHeight =
                  screenSize.height * _createTokenDialogHeightFactor;
              final theme = FluentTheme.of(dialogContext);

              return ChangeNotifierProvider<ClientTokenProvider>.value(
                value: provider,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: dialogWidth,
                      maxWidth: dialogWidth,
                    ),
                    child: Card(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      backgroundColor:
                          theme.resources.solidBackgroundFillColorBase,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditingToken
                                ? AppStrings.ctDialogEditTokenTitle
                                : AppStrings.ctDialogCreateTokenTitle,
                            style: theme.typography.subtitle,
                          ),
                          if (isEditingToken) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: theme.resources.subtleFillColorSecondary,
                                border: Border.all(
                                  color:
                                      theme.resources.controlStrokeColorDefault,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: const Text(
                                AppStrings.ctEditUpdatesTokenHint,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: dialogMaxHeight,
                            ),
                            child: Consumer<ClientTokenProvider>(
                              builder: (context, provider, _) {
                                return _CreateTokenDialogContent(
                                  clientIdController: _clientIdController,
                                  agentIdController: _agentIdController,
                                  payloadController: _payloadController,
                                  rules: _rules,
                                  allTables: _allTables,
                                  allViews: _allViews,
                                  allPermissions: _allPermissions,
                                  formError: _formError,
                                  providerError: provider.error,
                                  lastCreatedToken: provider.lastCreatedToken,
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
                                  onEditRule: _openEditRuleModal,
                                  onDeleteRule: _removeRule,
                                  onDismissCreatedToken:
                                      provider.clearLastCreatedToken,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Consumer<ClientTokenProvider>(
                            builder: (context, provider, _) {
                              return _CreateTokenDialogFooter(
                                isCreating: provider.isCreating,
                                submitLabel: isEditingToken
                                    ? AppStrings.ctButtonSaveTokenChanges
                                    : AppStrings.ctButtonCreateToken,
                                onCancel: () =>
                                    Navigator.of(dialogContext).pop(),
                                onSubmit: _handleSubmitToken,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
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
      _formError = AppStrings.ctErrorRuleOrAllPermissionsRequired;
      _notifyCreateTokenDialogChanged();
      return;
    }

    final request = ClientTokenCreateRequest(
      clientId: clientId,
      agentId: _agentIdController.text.trim().isEmpty
          ? null
          : _agentIdController.text.trim(),
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
    final rawPayload = _payloadController.text.trim();
    if (rawPayload.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      _formError = AppStrings.ctErrorPayloadMustBeJsonObject;
      _notifyCreateTokenDialogChanged();
      return null;
    } on FormatException {
      _formError = AppStrings.ctErrorPayloadInvalidJson;
      _notifyCreateTokenDialogChanged();
      return null;
    }
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
    return switch (value) {
      ClientTokenStatusFilter.all => AppStrings.ctFilterStatusAll,
      ClientTokenStatusFilter.active => AppStrings.ctFilterStatusActive,
      ClientTokenStatusFilter.revoked => AppStrings.ctFilterStatusRevoked,
    };
  }

  String _sortFilterLabel(ClientTokenSortOption value) {
    return switch (value) {
      ClientTokenSortOption.newest => AppStrings.ctSortNewest,
      ClientTokenSortOption.oldest => AppStrings.ctSortOldest,
      ClientTokenSortOption.clientAsc => AppStrings.ctSortClientAsc,
      ClientTokenSortOption.clientDesc => AppStrings.ctSortClientDesc,
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
    if (!getIt.isRegistered<SharedPreferences>()) {
      return;
    }
    final prefs = getIt<SharedPreferences>();
    try {
      final clientFilter = prefs.getString(_tokenClientFilterKey) ?? '';
      final statusFilter = _statusFilterFromStorage(
        prefs.getString(_tokenStatusFilterKey),
      );
      final sortFilter = _sortFilterFromStorage(
        prefs.getString(_tokenSortFilterKey),
      );
      final autoRefreshAfterCreate =
          prefs.getBool(_tokenAutoRefreshAfterCreateKey) ?? true;
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
    if (!getIt.isRegistered<SharedPreferences>()) {
      return;
    }
    final prefs = getIt<SharedPreferences>();
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
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: AppStrings.ctConfirmRevokeTitle,
      message: AppStrings.ctConfirmRevokeMessage,
      confirmText: AppStrings.ctButtonRevoke,
    );
    if (!mounted || !confirmed) {
      return;
    }
    await provider.revokeToken(token.id);
    if (!context.mounted) return;
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleError,
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
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: AppStrings.ctConfirmDeleteTitle,
      message: AppStrings.ctConfirmDeleteMessage,
      confirmText: AppStrings.ctButtonDelete,
    );
    if (!mounted || !confirmed) {
      return;
    }
    await provider.deleteToken(token.id);
    if (!context.mounted) return;
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleError,
        message: provider.error,
        onConfirm: () => provider.clearError(),
      );
    }
  }

  void _handleClientFilterChanged(String _) {
    _clientFilterDebounceTimer?.cancel();
    _clientFilterDebounceTimer = Timer(
      const Duration(milliseconds: 250),
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
        final listedTokens = provider.tokens;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SettingsSectionTitle(
                      title: AppStrings.ctSectionTitle,
                    ),
                  ),
                  AppButton(
                    label: AppStrings.ctButtonNewToken,
                    isPrimary: false,
                    icon: FluentIcons.add,
                    onPressed: _openCreateTokenModal,
                  ),
                ],
              ),
              if (provider.error.isNotEmpty) ...[
                InlineFeedbackCard(
                  severity: InfoBarSeverity.error,
                  title: AppStrings.modalTitleError,
                  message: provider.error,
                  onDismiss: provider.clearError,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  AppButton(
                    label: AppStrings.ctButtonRefreshList,
                    icon: FluentIcons.refresh,
                    isPrimary: false,
                    isLoading: provider.isLoading,
                    onPressed: () =>
                        provider.loadTokens(query: _buildListQuery()),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppButton(
                    label: _autoRefreshAfterCreate
                        ? AppStrings.ctButtonAutoRefreshOn
                        : AppStrings.ctButtonAutoRefreshOff,
                    icon: _autoRefreshAfterCreate
                        ? FluentIcons.sync
                        : FluentIcons.pause,
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
              const SettingsSectionTitle(
                title: AppStrings.ctSectionRegisteredTokens,
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
                  _hasActiveFilters()
                      ? AppStrings.ctMsgNoTokenMatchFilter
                      : AppStrings.ctMsgNoTokenFound,
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
                          builder: (context, close) => const InfoBar(
                            title: Text(
                              AppStrings.ctInfoClientTokenUnavailable,
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
                        builder: (context, close) => const InfoBar(
                          title: Text(AppStrings.ctInfoClientTokenCopied),
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

class _CreateTokenDialogContent extends StatelessWidget {
  const _CreateTokenDialogContent({
    required this.clientIdController,
    required this.agentIdController,
    required this.payloadController,
    required this.rules,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onToggleAllTables,
    required this.onToggleAllViews,
    required this.onToggleAllPermissions,
    required this.onAddRule,
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onDismissCreatedToken,
  });

  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final TextEditingController payloadController;
  final List<ClientTokenRuleDraft> rules;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final ValueChanged<bool> onToggleAllTables;
  final ValueChanged<bool> onToggleAllViews;
  final ValueChanged<bool> onToggleAllPermissions;
  final VoidCallback onAddRule;
  final ValueChanged<int> onEditRule;
  final ValueChanged<int> onDeleteRule;
  final VoidCallback onDismissCreatedToken;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 780;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TokenIdentityFields(
                clientIdController: clientIdController,
                agentIdController: agentIdController,
                isCompact: isCompact,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: AppStrings.ctFieldPayloadJsonOptional,
                controller: payloadController,
                hint: AppStrings.ctHintPayloadJson,
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _FlagCheckbox(
                    label: AppStrings.ctFlagAllTables,
                    value: allTables,
                    onChanged: onToggleAllTables,
                  ),
                  _FlagCheckbox(
                    label: AppStrings.ctFlagAllViews,
                    value: allViews,
                    onChanged: onToggleAllViews,
                  ),
                  _FlagCheckbox(
                    label: AppStrings.ctFlagAllPermissions,
                    value: allPermissions,
                    onChanged: onToggleAllPermissions,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(
                    child: SettingsSectionTitle(
                      title: AppStrings.ctSectionRulesByResource,
                    ),
                  ),
                  AppButton(
                    label: AppStrings.ctButtonAddRule,
                    isPrimary: false,
                    icon: FluentIcons.add,
                    onPressed: allPermissions ? null : onAddRule,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (rules.isEmpty)
                const Text(AppStrings.ctNoRulesAdded)
              else
                ClientTokenRulesGrid(
                  rules: rules,
                  onEdit: onEditRule,
                  onDelete: onDeleteRule,
                ),
              _TokenFeedbackPanel(
                formError: formError,
                providerError: providerError,
                lastCreatedToken: lastCreatedToken,
                onDismissCreatedToken: onDismissCreatedToken,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreateTokenDialogFooter extends StatelessWidget {
  const _CreateTokenDialogFooter({
    required this.isCreating,
    required this.submitLabel,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool isCreating;
  final String submitLabel;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: AppStrings.btnCancel,
          isPrimary: false,
          onPressed: onCancel,
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          label: submitLabel,
          isLoading: isCreating,
          onPressed: isCreating ? null : onSubmit,
        ),
      ],
    );
  }
}

class _TokenListFilters extends StatelessWidget {
  const _TokenListFilters({
    required this.clientFilterController,
    required this.tokenStatusFilter,
    required this.tokenSortOption,
    required this.onClientFilterChanged,
    required this.statusLabelBuilder,
    required this.sortLabelBuilder,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final TextEditingController clientFilterController;
  final ClientTokenStatusFilter tokenStatusFilter;
  final ClientTokenSortOption tokenSortOption;
  final ValueChanged<String> onClientFilterChanged;
  final String Function(ClientTokenStatusFilter) statusLabelBuilder;
  final String Function(ClientTokenSortOption) sortLabelBuilder;
  final ValueChanged<ClientTokenStatusFilter> onStatusChanged;
  final ValueChanged<ClientTokenSortOption> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: AppStrings.ctFilterClientId,
            controller: clientFilterController,
            hint: AppStrings.ctHintClientId,
            onChanged: onClientFilterChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: AppDropdown<ClientTokenStatusFilter>(
            label: AppStrings.ctFilterStatus,
            value: tokenStatusFilter,
            items: ClientTokenStatusFilter.values
                .map(
                  (item) => ComboBoxItem<ClientTokenStatusFilter>(
                    value: item,
                    child: Text(statusLabelBuilder(item)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: AppDropdown<ClientTokenSortOption>(
            label: AppStrings.ctFilterSort,
            value: tokenSortOption,
            items: ClientTokenSortOption.values
                .map(
                  (item) => ComboBoxItem<ClientTokenSortOption>(
                    value: item,
                    child: Text(sortLabelBuilder(item)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onSortChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        AppButton(
          label: AppStrings.ctButtonClearFilters,
          isPrimary: false,
          icon: FluentIcons.clear_filter,
          onPressed: onClearFilters,
        ),
      ],
    );
  }
}

class _TokenIdentityFields extends StatelessWidget {
  const _TokenIdentityFields({
    required this.clientIdController,
    required this.agentIdController,
    required this.isCompact,
  });

  final TextEditingController clientIdController;
  final TextEditingController agentIdController;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final Widget clientField = AppTextField(
      label: AppStrings.ctFieldClientId,
      controller: clientIdController,
      hint: AppStrings.ctHintClientId,
      readOnly: true,
      suffixIcon: _CopyValueButton(value: clientIdController.text),
    );

    final Widget agentField = AppTextField(
      label: AppStrings.ctFieldAgentIdOptional,
      controller: agentIdController,
      hint: AppStrings.ctHintAgentId,
    );

    if (isCompact) {
      return Column(
        children: [
          clientField,
          const SizedBox(height: AppSpacing.md),
          agentField,
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: clientField),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 2, child: agentField),
      ],
    );
  }
}

class _CopyValueButton extends StatelessWidget {
  const _CopyValueButton({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(FluentIcons.copy, size: 16),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
      },
    );
  }
}

class _TokenFeedbackPanel extends StatelessWidget {
  const _TokenFeedbackPanel({
    required this.formError,
    required this.providerError,
    required this.lastCreatedToken,
    required this.onDismissCreatedToken,
  });

  final String formError;
  final String providerError;
  final String? lastCreatedToken;
  final VoidCallback onDismissCreatedToken;

  @override
  Widget build(BuildContext context) {
    final feedbackWidgets = <Widget>[
      if (formError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: formError,
        ),
      if (providerError.isNotEmpty)
        InlineFeedbackCard(
          severity: InfoBarSeverity.error,
          message: providerError,
        ),
      if (lastCreatedToken != null)
        InlineFeedbackCard(
          severity: InfoBarSeverity.success,
          title: AppStrings.ctMsgTokenCreatedCopyNow,
          content: SelectableText(lastCreatedToken!),
          onDismiss: onDismissCreatedToken,
        ),
    ];

    if (feedbackWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: List<Widget>.generate(feedbackWidgets.length, (index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == feedbackWidgets.length - 1 ? 0 : AppSpacing.md,
            ),
            child: feedbackWidgets[index],
          );
        }),
      ),
    );
  }
}

class _FlagCheckbox extends StatelessWidget {
  const _FlagCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      checked: value,
      onChanged: (isChecked) => onChanged(isChecked ?? false),
      content: Text(label),
    );
  }
}

const _tokenGridColumns = [
  AppGridColumn(label: AppStrings.ctLabelClient, flex: 3),
  AppGridColumn(label: AppStrings.ctLabelId, flex: 4),
  AppGridColumn(label: AppStrings.ctLabelStatus, flex: 2),
  AppGridColumn(label: AppStrings.ctLabelScope, flex: 2),
  AppGridColumn(
    label: AppStrings.ctLabelCreatedAt,
    flex: 3,
    alignment: Alignment.center,
  ),
  AppGridColumn(
    label: AppStrings.ctGridColumnActions,
    flex: 4,
    alignment: Alignment.center,
  ),
];

class _TokenSummaryGrid extends StatelessWidget {
  const _TokenSummaryGrid({
    required this.tokens,
    required this.isRevokingToken,
    required this.isDeletingToken,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onRevoke,
    required this.onDelete,
    this.scrollController,
  });

  final List<ClientTokenSummary> tokens;
  final ScrollController? scrollController;
  final bool Function(String tokenId) isRevokingToken;
  final bool Function(String tokenId) isDeletingToken;
  final ValueChanged<ClientTokenSummary> onViewDetails;
  final ValueChanged<ClientTokenSummary> onCopyClientToken;
  final ValueChanged<ClientTokenSummary> onEdit;
  final ValueChanged<ClientTokenSummary> onRevoke;
  final ValueChanged<ClientTokenSummary> onDelete;

  String _buildScopeLabel(ClientTokenSummary token) {
    if (token.allPermissions) return AppStrings.ctScopeAllPermissions;
    final scopes = <String>[
      if (token.allTables) AppStrings.ctScopeTables,
      if (token.allViews) AppStrings.ctScopeViews,
    ];
    return scopes.isEmpty ? AppStrings.ctScopeRestricted : scopes.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AppDataGridScrollable<ClientTokenSummary>(
      columns: _tokenGridColumns,
      rows: tokens,
      scrollController: scrollController,
      rowCells: (token) => [
        SelectableText(token.clientId),
        SelectableText(token.id),
        Text(
          token.isRevoked
              ? AppStrings.ctStatusRevoked
              : AppStrings.ctStatusActive,
        ),
        Text(_buildScopeLabel(token)),
        Text(
          DateFormat('dd/MM/yyyy HH:mm').format(token.createdAt.toLocal()),
        ),
        _TokenRowActions(
          token: token,
          isRevoking: isRevokingToken(token.id),
          isDeleting: isDeletingToken(token.id),
          onViewDetails: () => onViewDetails(token),
          onCopyClientToken: () => onCopyClientToken(token),
          onEdit: () => onEdit(token),
          onRevoke: token.isRevoked ? null : () => onRevoke(token),
          onDelete: () => onDelete(token),
        ),
      ],
    );
  }
}

class _TokenRowActions extends StatelessWidget {
  const _TokenRowActions({
    required this.token,
    required this.isRevoking,
    required this.isDeleting,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onDelete,
    this.onRevoke,
  });

  final ClientTokenSummary token;
  final bool isRevoking;
  final bool isDeleting;
  final VoidCallback onViewDetails;
  final VoidCallback onCopyClientToken;
  final VoidCallback onEdit;
  final VoidCallback? onRevoke;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final revokeTooltip = token.isRevoked
        ? AppStrings.ctButtonRevoked
        : AppStrings.ctButtonRevoke;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Tooltip(
          message: AppStrings.ctTooltipEditToken,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonEdit,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: onEdit,
            ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctButtonViewDetails,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonViewDetails,
            child: IconButton(
              icon: const Icon(FluentIcons.view),
              onPressed: onViewDetails,
            ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctTooltipCopyClientToken,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonCopyClientToken,
            child: IconButton(
              icon: const Icon(FluentIcons.copy),
              onPressed: onCopyClientToken,
            ),
          ),
        ),
        Tooltip(
          message: revokeTooltip,
          child: Semantics(
            button: true,
            label: revokeTooltip,
            child: isRevoking
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(FluentIcons.block_contact),
                    onPressed: onRevoke,
                  ),
          ),
        ),
        Tooltip(
          message: AppStrings.ctButtonDelete,
          child: Semantics(
            button: true,
            label: AppStrings.ctButtonDelete,
            child: isDeleting
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(FluentIcons.delete),
                    onPressed: onDelete,
                  ),
          ),
        ),
      ],
    );
  }
}
