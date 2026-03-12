import 'dart:async';
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_details_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
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
const _createTokenRulesMaxHeight = 280.0;
const _createTokenRulesMinTableWidth = 780.0;

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

  bool _allTables = false;
  bool _allViews = false;
  bool _allPermissions = false;
  _TokenStatusFilter _tokenStatusFilter = _TokenStatusFilter.all;
  _TokenSortOption _tokenSortOption = _TokenSortOption.newest;
  bool _autoRefreshAfterCreate = true;
  bool _keepConfigAfterCreate = false;
  String _formError = '';

  @override
  void initState() {
    super.initState();
    _restoreTokenListPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final provider = context.read<ClientTokenProvider>();
      if (!provider.hasLoaded) {
        provider.loadTokens(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _agentIdController.dispose();
    _payloadController.dispose();
    _listClientFilterController.dispose();
    _clientFilterDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAddRuleModal() async {
    final result = await showClientTokenRuleDialog(context: context);
    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _rules.add(result);
    });
  }

  Future<void> _openEditRuleModal(int index) async {
    final currentRule = _rules[index];
    final result = await showClientTokenRuleDialog(
      context: context,
      initialRule: currentRule,
    );
    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _rules[index] = result;
    });
  }

  Future<void> _removeRule(int index) async {
    final rule = _rules[index];
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: AppStrings.ctDialogDeleteRuleTitle,
      message: AppStrings.ctDeleteRuleConfirmation(
        resourceType: rule.resourceType.name,
        resourceName: rule.resource,
      ),
      confirmText: AppStrings.ctButtonDeleteRule,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _rules.removeAt(index);
    });
  }

  Future<void> _openCreateTokenModal() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _formError = '';
    });
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final availableWidth =
            screenSize.width - (_createTokenDialogHorizontalMargin * 2);
        final dialogWidth = availableWidth.clamp(
          420.0,
          _createTokenDialogMaxWidth,
        );
        final dialogMaxHeight =
            screenSize.height * _createTokenDialogHeightFactor;

        return Center(
          child: SizedBox(
            width: dialogWidth,
            child: ContentDialog(
              title: const Text(AppStrings.ctDialogCreateTokenTitle),
              content: ConstrainedBox(
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
                      isCreating: provider.isCreating,
                      keepConfigAfterCreate: _keepConfigAfterCreate,
                      onToggleAllTables: (value) {
                        setState(() {
                          _allTables = value;
                        });
                      },
                      onToggleAllViews: (value) {
                        setState(() {
                          _allViews = value;
                        });
                      },
                      onToggleAllPermissions: (value) {
                        setState(() {
                          _allPermissions = value;
                        });
                      },
                      onAddRule: _openAddRuleModal,
                      onEditRule: _openEditRuleModal,
                      onDeleteRule: _removeRule,
                      onDismissCreatedToken: provider.clearLastCreatedToken,
                      onToggleKeepConfigAfterCreate: (value) {
                        setState(() {
                          _keepConfigAfterCreate = value;
                        });
                      },
                      onCreateToken: _handleCreateToken,
                    );
                  },
                ),
              ),
              actions: [
                Button(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(AppStrings.btnCancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCreateToken() async {
    setState(() {
      _formError = '';
    });

    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() {
        _formError = AppStrings.ctErrorClientIdRequired;
      });
      return;
    }

    final payloadResult = _parsePayload();
    if (payloadResult == null) {
      return;
    }

    final rules = _buildRules();
    if (!_allPermissions && rules.isEmpty) {
      setState(() {
        _formError = AppStrings.ctErrorRuleOrAllPermissionsRequired;
      });
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
    final created = await provider.createToken(
      request,
      refreshTokens: false,
    );
    if (created && mounted) {
      if (_autoRefreshAfterCreate) {
        await _refreshTokensPreservingPosition(previousOffset);
      }
      setState(() {
        _formError = '';
        if (!_keepConfigAfterCreate) {
          _clearTokenDraftForm();
        }
      });
    }
  }

  void _clearTokenDraftForm() {
    _clientIdController.clear();
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
      setState(() {
        _formError = AppStrings.ctErrorPayloadMustBeJsonObject;
      });
      return null;
    } on FormatException {
      setState(() {
        _formError = AppStrings.ctErrorPayloadInvalidJson;
      });
      return null;
    }
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

  List<ClientTokenSummary> _applyTokenFilters(List<ClientTokenSummary> tokens) {
    final clientFilter = _listClientFilterController.text.trim().toLowerCase();
    final filtered = tokens.where((token) {
      final matchesClient =
          clientFilter.isEmpty ||
          token.clientId.toLowerCase().contains(clientFilter);
      final matchesStatus = switch (_tokenStatusFilter) {
        _TokenStatusFilter.all => true,
        _TokenStatusFilter.active => !token.isRevoked,
        _TokenStatusFilter.revoked => token.isRevoked,
      };
      return matchesClient && matchesStatus;
    }).toList();

    filtered.sort((left, right) {
      return switch (_tokenSortOption) {
        _TokenSortOption.newest => right.createdAt.compareTo(left.createdAt),
        _TokenSortOption.oldest => left.createdAt.compareTo(right.createdAt),
        _TokenSortOption.clientAsc => left.clientId.toLowerCase().compareTo(
          right.clientId.toLowerCase(),
        ),
        _TokenSortOption.clientDesc => right.clientId.toLowerCase().compareTo(
          left.clientId.toLowerCase(),
        ),
      };
    });

    return filtered;
  }

  String _statusFilterLabel(_TokenStatusFilter value) {
    return switch (value) {
      _TokenStatusFilter.all => AppStrings.ctFilterStatusAll,
      _TokenStatusFilter.active => AppStrings.ctFilterStatusActive,
      _TokenStatusFilter.revoked => AppStrings.ctFilterStatusRevoked,
    };
  }

  String _sortFilterLabel(_TokenSortOption value) {
    return switch (value) {
      _TokenSortOption.newest => AppStrings.ctSortNewest,
      _TokenSortOption.oldest => AppStrings.ctSortOldest,
      _TokenSortOption.clientAsc => AppStrings.ctSortClientAsc,
      _TokenSortOption.clientDesc => AppStrings.ctSortClientDesc,
    };
  }

  void _clearTokenFilters() {
    _listClientFilterController.clear();
    setState(() {
      _tokenStatusFilter = _TokenStatusFilter.all;
      _tokenSortOption = _TokenSortOption.newest;
    });
    _saveTokenListPreferences();
  }

  Future<void> _restoreTokenListPreferences() async {
    final prefs = getIt<SharedPreferences>();
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
  }

  Future<void> _saveTokenListPreferences() async {
    final prefs = getIt<SharedPreferences>();
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
  }

  String _statusFilterToStorage(_TokenStatusFilter value) {
    return switch (value) {
      _TokenStatusFilter.all => 'all',
      _TokenStatusFilter.active => 'active',
      _TokenStatusFilter.revoked => 'revoked',
    };
  }

  _TokenStatusFilter _statusFilterFromStorage(String? value) {
    return switch (value) {
      'active' => _TokenStatusFilter.active,
      'revoked' => _TokenStatusFilter.revoked,
      _ => _TokenStatusFilter.all,
    };
  }

  String _sortFilterToStorage(_TokenSortOption value) {
    return switch (value) {
      _TokenSortOption.newest => 'newest',
      _TokenSortOption.oldest => 'oldest',
      _TokenSortOption.clientAsc => 'client_asc',
      _TokenSortOption.clientDesc => 'client_desc',
    };
  }

  _TokenSortOption _sortFilterFromStorage(String? value) {
    return switch (value) {
      'oldest' => _TokenSortOption.oldest,
      'client_asc' => _TokenSortOption.clientAsc,
      'client_desc' => _TokenSortOption.clientDesc,
      _ => _TokenSortOption.newest,
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
    final refreshed = await provider.loadTokens(silent: true);
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

  void _handleClientFilterChanged(String _) {
    _clientFilterDebounceTimer?.cancel();
    _clientFilterDebounceTimer = Timer(
      const Duration(milliseconds: 250),
      () {
        if (!mounted) {
          return;
        }
        setState(() {});
        _saveTokenListPreferences();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientTokenProvider>(
      builder: (context, provider, _) {
        final filteredTokens = _applyTokenFilters(provider.tokens);
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
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppButton(
                    label: AppStrings.ctButtonRefreshList,
                    icon: FluentIcons.refresh,
                    isPrimary: false,
                    isLoading: provider.isLoading,
                    onPressed: () => provider.loadTokens(),
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
              const SizedBox(height: AppSpacing.lg),
              const SettingsSectionTitle(
                title: AppStrings.ctSectionRegisteredTokens,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      label: AppStrings.ctFilterClientId,
                      controller: _listClientFilterController,
                      hint: AppStrings.ctHintClientId,
                      onChanged: _handleClientFilterChanged,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: AppDropdown<_TokenStatusFilter>(
                      label: AppStrings.ctFilterStatus,
                      value: _tokenStatusFilter,
                      items: _TokenStatusFilter.values
                          .map(
                            (item) => ComboBoxItem<_TokenStatusFilter>(
                              value: item,
                              child: Text(_statusFilterLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _tokenStatusFilter = value;
                        });
                        _saveTokenListPreferences();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: AppDropdown<_TokenSortOption>(
                      label: AppStrings.ctFilterSort,
                      value: _tokenSortOption,
                      items: _TokenSortOption.values
                          .map(
                            (item) => ComboBoxItem<_TokenSortOption>(
                              value: item,
                              child: Text(_sortFilterLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _tokenSortOption = value;
                        });
                        _saveTokenListPreferences();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppButton(
                    label: AppStrings.ctButtonClearFilters,
                    isPrimary: false,
                    icon: FluentIcons.clear_filter,
                    onPressed: _clearTokenFilters,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (provider.tokens.isEmpty && !provider.isLoading)
                const Text(AppStrings.ctMsgNoTokenFound),
              if (provider.tokens.isNotEmpty && filteredTokens.isEmpty)
                const Text(AppStrings.ctMsgNoTokenMatchFilter),
              if (filteredTokens.isNotEmpty)
                SizedBox(
                  height: 440,
                  child: ListView.builder(
                    controller: widget.scrollController,
                    itemCount: filteredTokens.length,
                    itemBuilder: (context, index) {
                      final token = filteredTokens[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TokenSummaryTile(
                          token: token,
                          isRevoking: provider.isRevokingToken(token.id),
                          onViewDetails: () => showClientTokenDetailsDialog(
                            context: context,
                            token: token,
                          ),
                          onRevoke: token.isRevoked
                              ? null
                              : () => provider.revokeToken(token.id),
                        ),
                      );
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
    required this.isCreating,
    required this.keepConfigAfterCreate,
    required this.onToggleAllTables,
    required this.onToggleAllViews,
    required this.onToggleAllPermissions,
    required this.onAddRule,
    required this.onEditRule,
    required this.onDeleteRule,
    required this.onDismissCreatedToken,
    required this.onToggleKeepConfigAfterCreate,
    required this.onCreateToken,
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
  final bool isCreating;
  final bool keepConfigAfterCreate;
  final ValueChanged<bool> onToggleAllTables;
  final ValueChanged<bool> onToggleAllViews;
  final ValueChanged<bool> onToggleAllPermissions;
  final Future<void> Function() onAddRule;
  final Future<void> Function(int index) onEditRule;
  final Future<void> Function(int index) onDeleteRule;
  final VoidCallback onDismissCreatedToken;
  final ValueChanged<bool> onToggleKeepConfigAfterCreate;
  final Future<void> Function() onCreateToken;

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
              if (isCompact) ...[
                AppTextField(
                  label: AppStrings.ctFieldClientId,
                  controller: clientIdController,
                  hint: AppStrings.ctHintClientId,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: AppStrings.ctFieldAgentIdOptional,
                  controller: agentIdController,
                  hint: AppStrings.ctHintAgentId,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        label: AppStrings.ctFieldClientId,
                        controller: clientIdController,
                        hint: AppStrings.ctHintClientId,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: AppTextField(
                        label: AppStrings.ctFieldAgentIdOptional,
                        controller: agentIdController,
                        hint: AppStrings.ctHintAgentId,
                      ),
                    ),
                  ],
                ),
              ],
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
                    onPressed: onAddRule,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (rules.isEmpty)
                const Text(AppStrings.ctNoRulesAdded)
              else
                Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth:
                            constraints.maxWidth >=
                                _createTokenRulesMinTableWidth
                            ? constraints.maxWidth
                            : _createTokenRulesMinTableWidth,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: _createTokenRulesMaxHeight,
                        ),
                        child: SingleChildScrollView(
                          child: ClientTokenRulesGrid(
                            rules: rules,
                            onEdit: onEditRule,
                            onDelete: onDeleteRule,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (formError.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorSurface(message: formError),
              ],
              if (providerError.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorSurface(message: providerError),
              ],
              if (lastCreatedToken != null) ...[
                const SizedBox(height: AppSpacing.md),
                _CreatedTokenSurface(
                  token: lastCreatedToken!,
                  onDismiss: onDismissCreatedToken,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _FlagCheckbox(
                label: AppStrings.ctToggleKeepConfigAfterCreate,
                value: keepConfigAfterCreate,
                onChanged: onToggleKeepConfigAfterCreate,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: AppStrings.ctButtonCreateToken,
                icon: FluentIcons.add_friend,
                isLoading: isCreating,
                onPressed: onCreateToken,
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TokenStatusFilter {
  all,
  active,
  revoked,
}

enum _TokenSortOption {
  newest,
  oldest,
  clientAsc,
  clientDesc,
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

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SelectableText(
        message,
        style: TextStyle(
          color: Colors.red.normal,
        ),
      ),
    );
  }
}

class _CreatedTokenSurface extends StatelessWidget {
  const _CreatedTokenSurface({
    required this.token,
    required this.onDismiss,
  });

  final String token;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  AppStrings.ctMsgTokenCreatedCopyNow,
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.clear),
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(token),
        ],
      ),
    );
  }
}

class _TokenSummaryTile extends StatelessWidget {
  const _TokenSummaryTile({
    required this.token,
    required this.isRevoking,
    required this.onViewDetails,
    this.onRevoke,
  });

  final ClientTokenSummary token;
  final bool isRevoking;
  final VoidCallback onViewDetails;
  final VoidCallback? onRevoke;

  String _buildScopeLabel() {
    if (token.allPermissions) {
      return AppStrings.ctScopeAllPermissions;
    }
    final scopes = <String>[];
    if (token.allTables) {
      scopes.add(AppStrings.ctScopeTables);
    }
    if (token.allViews) {
      scopes.add(AppStrings.ctScopeViews);
    }
    if (scopes.isEmpty) {
      return AppStrings.ctScopeRestricted;
    }
    return '${AppStrings.ctScopeRestricted} (${scopes.join(', ')})';
  }

  String _buildRulesLabel() {
    if (token.rules.isEmpty) {
      return AppStrings.ctScopeNotInformed;
    }
    return '${token.rules.length}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '${AppStrings.ctLabelClient}: ${token.clientId}',
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText('${AppStrings.ctLabelId}: ${token.id}'),
                if (token.agentId != null &&
                    token.agentId!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    '${AppStrings.ctLabelAgent}: ${token.agentId}',
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${AppStrings.ctLabelCreatedAt}: '
                  '${token.createdAt.toLocal().toIso8601String()}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${AppStrings.ctLabelStatus}: '
                  '${token.isRevoked ? AppStrings.ctStatusRevoked : AppStrings.ctStatusActive}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('${AppStrings.ctLabelScope}: ${_buildScopeLabel()}'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${AppStrings.ctLabelRules}: ${_buildRulesLabel()}',
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppButton(
                label: AppStrings.ctButtonViewDetails,
                isPrimary: false,
                icon: FluentIcons.view,
                onPressed: onViewDetails,
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(
                label: token.isRevoked
                    ? AppStrings.ctButtonRevoked
                    : AppStrings.ctButtonRevoke,
                isPrimary: false,
                isLoading: isRevoking,
                onPressed: onRevoke,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
