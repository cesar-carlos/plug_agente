import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_flow.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_panel.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_coordinator.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_details_dialog.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
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
  late final ClientTokenSectionCoordinator _coordinator;
  var _controllerInitialized = false;
  ClientTokenSubmitFeedback? _savedFeedback;
  late final ScrollController _listScrollController;
  late final bool _ownsScrollController;

  @override
  void initState() {
    super.initState();
    _ownsScrollController = widget.scrollController == null;
    _listScrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllerInitialized) {
      _controllerInitialized = true;
      _controller = ClientTokenSectionController(
        settingsStoreLookup: () => readOptionalGetItService<IAppSettingsStore>(),
        onSectionChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
      );
      _coordinator = ClientTokenSectionCoordinator(
        controller: _controller,
        scrollController: _listScrollController,
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
    if (!mounted) {
      return;
    }
    await _coordinator.initializeTokenListState(context.read<ClientTokenProvider>());
  }

  @override
  void dispose() {
    if (_controllerInitialized) {
      _controller.dispose();
    }
    if (_ownsScrollController) _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _openCreateTokenModal([ClientTokenSummary? baseToken]) async {
    if (!mounted) {
      return;
    }
    final provider = context.read<ClientTokenProvider>();
    final feedback = await showClientTokenCreateDialog(
      context: context,
      controller: _controller,
      coordinator: _coordinator,
      provider: provider,
      baseToken: baseToken,
    );
    if (mounted) {
      if (feedback != null) {
        if (feedback.tokenValue != null) {
          _savedFeedback = feedback;
        } else {
          _coordinator.showEditOutcomeFeedback(
            context: context,
            outcome: feedback.outcome,
            rotatedTokenValue: feedback.tokenValue,
          );
        }
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      ClientTokenProvider,
      ({
        List<ClientTokenSummary> tokens,
        bool isLoading,
        bool hasLoaded,
        bool isMutating,
        String error,
        String listError,
        bool isListStale,
        int page,
        int pageSize,
        int totalCount,
        String? revokingId,
        String? deletingId,
        String? copyingId,
      })
    >(
      selector: (_, provider) => (
        tokens: provider.tokens,
        isLoading: provider.isLoading,
        hasLoaded: provider.hasLoaded,
        isMutating: provider.isTokenMutationInProgress,
        error: provider.mutationError,
        listError: provider.listError,
        isListStale: provider.isListStale,
        page: provider.currentPage,
        pageSize: provider.pageSize,
        totalCount: provider.totalCount,
        revokingId: provider.revokingTokenId,
        deletingId: provider.deletingTokenId,
        copyingId: provider.copyingTokenSecretId,
      ),
      builder: (context, state, _) {
        final provider = context.read<ClientTokenProvider>();
        final l10n = AppLocalizations.of(context)!;
        final listedTokens = state.tokens;
        final isInitialLoading = state.isLoading && !state.hasLoaded;
        final isListInteractionLocked = state.isMutating;
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
              if (_savedFeedback?.tokenValue case final String tokenValue) ...[
                const SizedBox(height: AppSpacing.sm),
                InfoBar(
                  title: Text(_savedFeedback!.isCreation ? l10n.ctMsgTokenCreatedCopyNow : l10n.ctMsgTokenRotated),
                  content: SelectableText(tokenValue),
                  severity: InfoBarSeverity.success,
                  onClose: () => setState(() => _savedFeedback = null),
                  action: FilledButton(
                    onPressed: () => Clipboard.setData(ClipboardData(text: tokenValue)),
                    child: Text(l10n.ctButtonCopyToken),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (state.error.isNotEmpty) ...[
                InlineFeedbackCard(
                  severity: InfoBarSeverity.error,
                  title: l10n.modalTitleError,
                  message: state.error,
                  onDismiss: provider.clearError,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (state.listError.isNotEmpty || state.isListStale) ...[
                InlineFeedbackCard(
                  severity: state.hasLoaded ? InfoBarSeverity.warning : InfoBarSeverity.error,
                  title: state.isListStale ? l10n.ctSavedListStale : l10n.modalTitleError,
                  message: state.listError.isNotEmpty ? state.listError : l10n.ctListStale,
                  onRetry: state.hasLoaded && !isListInteractionLocked
                      ? () => _coordinator.refreshList(provider)
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_controller.hasPreferenceWarning) ...[
                InlineFeedbackCard(severity: InfoBarSeverity.warning, message: l10n.ctPreferencesSaveFailed),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
              ClientTokenListPanel(
                listedTokens: listedTokens,
                isInitialLoading: isInitialLoading,
                isListInteractionLocked: isListInteractionLocked,
                hasLoaded: state.hasLoaded,
                isLoading: state.isLoading,
                hasLoadError: state.listError.isNotEmpty,
                hasActiveFilters: _controller.hasActiveFilters(),
                clientFilterController: _controller.listClientFilterController,
                tokenStatusFilter: _controller.tokenStatusFilter,
                tokenSortOption: _controller.tokenSortOption,
                autoRefreshAfterCreate: _controller.autoRefreshAfterCreate,
                statusLabelBuilder: (value) => ClientTokenSectionCoordinator.statusFilterLabel(l10n, value),
                sortLabelBuilder: (value) => ClientTokenSectionCoordinator.sortFilterLabel(l10n, value),
                onClientFilterChanged: (_) {
                  _controller.handleClientFilterChanged(() async {
                    if (!mounted) {
                      return;
                    }
                    await _controller.saveListPreferences();
                    await _coordinator.reloadTokensForCurrentFilters(provider);
                  });
                },
                onStatusChanged: (value) async {
                  _controller.updateTokenStatusFilter(value);
                  await _controller.saveListPreferences();
                  await _coordinator.reloadTokensForCurrentFilters(provider);
                },
                onSortChanged: (value) async {
                  _controller.updateTokenSortOption(value);
                  await _controller.saveListPreferences();
                  await _coordinator.reloadTokensForCurrentFilters(provider);
                },
                onClearFilters: () => _coordinator.clearTokenFilters(provider),
                onRefresh: () => _coordinator.refreshList(provider),
                onToggleAutoRefresh: () async {
                  _controller.toggleAutoRefreshAfterCreate();
                  await _controller.saveListPreferences();
                },
                onRetryLoad: () => _coordinator.refreshList(provider),
                page: state.page,
                pageSize: _controller.pageSize,
                totalCount: state.totalCount,
                onPageChanged: (page) => _coordinator.changePage(provider, page),
                onPageSizeChanged: (size) => _coordinator.changePageSize(provider, size),
                scrollController: _listScrollController,
                isRevokingToken: provider.isRevokingToken,
                isDeletingToken: provider.isDeletingToken,
                isCopyingTokenSecret: provider.isCopyingTokenSecretFor,
                onViewDetails: (token) => showClientTokenDetailsDialog(
                  context: context,
                  token: token,
                ),
                onCopyClientToken: (token) {
                  unawaited(_coordinator.handleCopyToken(context, provider, token));
                },
                onEdit: _openCreateTokenModal,
                onRevoke: (token) {
                  _coordinator.handleRevoke(context, provider, token);
                },
                onDelete: (token) {
                  _coordinator.handleDelete(context, provider, token);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
