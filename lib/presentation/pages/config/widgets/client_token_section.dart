import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' show max, min;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_content.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_footer.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_shell.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_panel.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_details_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_file_service.dart';
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
  late final ClientTokenSectionController _controller;
  var _controllerInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllerInitialized) {
      _controllerInitialized = true;
      _controller = ClientTokenSectionController(
        settingsStoreLookup: () => readOptionalPresentationProvider<IAppSettingsStore>(context),
        onSectionChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_initializeTokenListState());
      });
    }
  }

  Future<void> _initializeTokenListState() async {
    final restored = _controller.restoreListPreferences();
    if (restored != null && mounted) {
      setState(() => _controller.applyRestoredListPreferences(restored));
    }
    if (!mounted) {
      return;
    }
    final provider = context.read<ClientTokenProvider>();
    if (!provider.hasLoaded) {
      await provider.loadTokens(query: _controller.buildListQuery());
    }
  }

  @override
  void dispose() {
    if (_controllerInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _formErrorMessage(AppLocalizations l10n) {
    return switch (_controller.formErrorKey) {
      ClientTokenFormErrorKey.globalPermissionRequired => l10n.ctErrorGlobalPermissionRequired,
      ClientTokenFormErrorKey.ruleOrGlobalPermissionsRequired => l10n.ctErrorRuleOrGlobalPermissionsRequired,
      ClientTokenFormErrorKey.payloadInvalidJson => l10n.ctErrorPayloadInvalidJson,
      ClientTokenFormErrorKey.payloadMustBeJsonObject => l10n.ctErrorPayloadMustBeJsonObject,
      ClientTokenFormErrorKey.payloadDatabaseMustBeString => l10n.ctErrorPayloadDatabaseMustBeString,
      ClientTokenFormErrorKey.payloadDatabaseCannotBeEmpty => l10n.ctErrorPayloadDatabaseCannotBeEmpty,
      null => '',
    };
  }

  Future<void> _openAddRuleModal() async {
    if (_controller.isGlobalScopeMode) {
      return;
    }
    final result = await showClientTokenRuleDialog(
      context: context,
      existingRules: List.unmodifiable(_controller.rules),
    );
    if (!mounted || result == null) return;

    _controller.mergeRules(result);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.notifyCreateTokenDialogChanged();
    });
  }

  Future<void> _openEditRuleModal(int index) async {
    final result = await showClientTokenRuleDialog(
      context: context,
      initialRule: _controller.rules[index],
      existingRules: List.unmodifiable(_controller.rules),
    );
    if (!mounted || result == null) return;

    _controller.rules[index] = result.first;
    _controller.notifyCreateTokenDialogChanged();
  }

  Future<void> _handleImportRulesFromSection() async {
    if (!mounted || _controller.isImportingRules || _controller.isGlobalScopeMode) return;
    final l10n = AppLocalizations.of(context)!;

    try {
      final picked = await _controller.pickRulesImportFile();
      if (picked == null || picked.files.isEmpty) return;
      final filePath = picked.files.single.path;
      if (filePath == null) return;

      _controller.setImportingRules(true);

      final outcome = await _controller.importRulesFromPath(filePath);
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
          _controller.mergeRules(drafts);
          _controller.notifyCreateTokenDialogChanged();
          SettingsFeedback.showSuccess(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesSuccess(drafts.length),
          );
      }
    } on Exception catch (e, st) {
      developer.log('Rule import picker failed', name: 'client_token_section', error: e, stackTrace: st);
      if (mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorReadFailed,
        );
      }
    } finally {
      if (mounted) _controller.setImportingRules(false);
    }
  }

  Future<void> _handleExportRules() async {
    if (_controller.rules.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    final tokenName = _controller.nameController.text.trim();
    final defaultFileName = tokenName.isNotEmpty
        ? '${tokenName.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '')}.txt'
        : l10n.ctExportRulesDefaultFileName;

    try {
      final savePath = await _controller.pickRulesExportPath(defaultFileName);
      if (savePath == null) return;
      await _controller.exportRulesToPath(savePath);
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

    setState(() => _controller.loadTokenIntoForm(baseToken));
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();
    provider.clearLastUpdateOutcome();

    _controller.attachDialogControllerListeners();
    _controller.markCreateTokenDialogOpen(true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierLabel: l10n.ctDialogDismissCreateToken,
        barrierColor: Colors.black.withValues(
          alpha: createTokenBarrierOpacity,
        ),
        pageBuilder: (_, primaryAnimation, secondaryAnimation) {
          return ValueListenableBuilder<int>(
            valueListenable: _controller.createTokenDialogRevision,
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
              final dialogL10n = AppLocalizations.of(dialogContext)!;
              final formError = _formErrorMessage(dialogL10n);

              return ChangeNotifierProvider<ClientTokenProvider>.value(
                value: provider,
                child: ClientTokenCreateDialogShell(
                  navigatorContext: dialogContext,
                  agentFocusNode: _controller.createTokenDialogAgentFocusNode,
                  dialogWidth: dialogWidth,
                  dialogOuterMaxHeight: dialogOuterMaxHeight,
                  theme: theme,
                  isEditingToken: isEditingToken,
                  body: (context, tokenProvider) {
                    final hasChanges = _controller.hasFormChanges();
                    final policyChanged = _controller.hasPolicyChanges();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClientTokenCreateDialogContent(
                            isCompact: isCompact,
                            isEditingToken: isEditingToken,
                            policyChanged: policyChanged,
                            hasFormChanges: hasChanges,
                            agentFocusNode: _controller.createTokenDialogAgentFocusNode,
                            nameController: _controller.nameController,
                            clientIdController: _controller.clientIdController,
                            agentIdController: _controller.agentIdController,
                            payloadController: _controller.payloadController,
                            rules: _controller.rules,
                            allTables: _controller.allTables,
                            allViews: _controller.allViews,
                            globalCanRead: _controller.globalCanRead,
                            globalCanUpdate: _controller.globalCanUpdate,
                            globalCanDelete: _controller.globalCanDelete,
                            globalCanDdl: _controller.globalCanDdl,
                            formError: formError,
                            providerError: tokenProvider.error,
                            lastCreatedToken: tokenProvider.lastCreatedToken,
                            onToggleAllTables: (value) {
                              _controller.allTables = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onToggleAllViews: (value) {
                              _controller.allViews = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalRead: (value) {
                              _controller.globalCanRead = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalUpdate: (value) {
                              _controller.globalCanUpdate = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalDelete: (value) {
                              _controller.globalCanDelete = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onToggleGlobalDdl: (value) {
                              _controller.globalCanDdl = value;
                              _controller.notifyCreateTokenDialogChanged();
                            },
                            onAddRule: _openAddRuleModal,
                            onExportRules: _handleExportRules,
                            onImportRules: _handleImportRulesFromSection,
                            isImportingRules: _controller.isImportingRules,
                            onEditRule: _openEditRuleModal,
                            onDeleteRule: _controller.removeRule,
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
      _controller.markCreateTokenDialogOpen(false);
      _controller.detachDialogControllerListeners();
    }
  }

  Future<void> _handleSubmitToken() async {
    _controller.clearFormError();
    _controller.notifyCreateTokenDialogChanged();

    final navigator = Navigator.of(context, rootNavigator: true);
    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    final request = _controller.buildSubmitRequest();
    if (request == null) {
      return;
    }

    final previousOffset = _getCurrentScrollOffset();
    final currentEditingTokenId = _controller.editingTokenId;
    final isSuccess = currentEditingTokenId == null
        ? await provider.createToken(
            request,
            refreshTokens: false,
          )
        : await provider.updateToken(
            currentEditingTokenId,
            request,
            refreshTokens: false,
            expectedVersion: _controller.editingTokenVersion,
          );

    if (isSuccess && mounted) {
      if (_controller.autoRefreshAfterCreate) {
        await _refreshTokensPreservingPosition(previousOffset);
      }
      if (!mounted) return;
      _controller.clearFormError();
      _controller.notifyCreateTokenDialogChanged();
      if (provider.error.isEmpty) {
        final outcome = provider.lastUpdateOutcome;
        final rotatedTokenValue = provider.lastCreatedToken;
        _controller.clearTokenDraftForm();
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

  Future<void> _clearTokenFilters() async {
    _controller.clearTokenFilters();
    await _controller.saveListPreferences();
    await _reloadTokensForCurrentFilters();
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
      query: _controller.buildListQuery(),
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

  Future<void> _reloadTokensForCurrentFilters() async {
    final provider = context.read<ClientTokenProvider>();
    await provider.loadTokens(
      silent: true,
      query: _controller.buildListQuery(),
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
                hasActiveFilters: _controller.hasActiveFilters(),
                clientFilterController: _controller.listClientFilterController,
                tokenStatusFilter: _controller.tokenStatusFilter,
                tokenSortOption: _controller.tokenSortOption,
                autoRefreshAfterCreate: _controller.autoRefreshAfterCreate,
                statusLabelBuilder: _statusFilterLabel,
                sortLabelBuilder: _sortFilterLabel,
                onClientFilterChanged: (_) {
                  _controller.handleClientFilterChanged(() async {
                    if (!mounted) {
                      return;
                    }
                    await _controller.saveListPreferences();
                    await _reloadTokensForCurrentFilters();
                  });
                },
                onStatusChanged: (value) async {
                  _controller.updateTokenStatusFilter(value);
                  await _controller.saveListPreferences();
                  await _reloadTokensForCurrentFilters();
                },
                onSortChanged: (value) async {
                  _controller.updateTokenSortOption(value);
                  await _controller.saveListPreferences();
                  await _reloadTokensForCurrentFilters();
                },
                onClearFilters: _clearTokenFilters,
                onRefresh: () => provider.loadTokens(query: _controller.buildListQuery()),
                onToggleAutoRefresh: () async {
                  _controller.toggleAutoRefreshAfterCreate();
                  await _controller.saveListPreferences();
                },
                onRetryLoad: () => provider.loadTokens(query: _controller.buildListQuery()),
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
