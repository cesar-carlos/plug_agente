import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
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
      _coordinator = ClientTokenSectionCoordinator(
        controller: _controller,
        scrollController: widget.scrollController,
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
    await _coordinator.initializeTokenListState(context.read<ClientTokenProvider>());
  }

  @override
  void dispose() {
    if (_controllerInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _openCreateTokenModal([ClientTokenSummary? baseToken]) async {
    if (!mounted) {
      return;
    }
    setState(() {});
    final provider = context.read<ClientTokenProvider>();
    await showClientTokenCreateDialog(
      context: context,
      controller: _controller,
      coordinator: _coordinator,
      provider: provider,
      baseToken: baseToken,
    );
    if (mounted) {
      setState(() {});
    }
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
