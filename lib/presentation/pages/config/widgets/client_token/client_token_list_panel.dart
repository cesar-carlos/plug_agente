import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_filters.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_toolbar.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_summary_grid.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class ClientTokenListPanel extends StatelessWidget {
  const ClientTokenListPanel({
    required this.listedTokens,
    required this.isInitialLoading,
    required this.isListInteractionLocked,
    required this.hasLoaded,
    required this.isLoading,
    required this.hasLoadError,
    required this.hasActiveFilters,
    required this.clientFilterController,
    required this.tokenStatusFilter,
    required this.tokenSortOption,
    required this.autoRefreshAfterCreate,
    required this.statusLabelBuilder,
    required this.sortLabelBuilder,
    required this.onClientFilterChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onClearFilters,
    required this.onRefresh,
    required this.onToggleAutoRefresh,
    required this.onRetryLoad,
    required this.isRevokingToken,
    required this.isDeletingToken,
    required this.isCopyingTokenSecret,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onRevoke,
    required this.onDelete,
    this.scrollController,
    super.key,
  });

  final List<ClientTokenSummary> listedTokens;
  final bool isInitialLoading;
  final bool isListInteractionLocked;
  final bool hasLoaded;
  final bool isLoading;
  final bool hasLoadError;
  final bool hasActiveFilters;
  final TextEditingController clientFilterController;
  final ClientTokenStatusFilter tokenStatusFilter;
  final ClientTokenSortOption tokenSortOption;
  final bool autoRefreshAfterCreate;
  final String Function(ClientTokenStatusFilter) statusLabelBuilder;
  final String Function(ClientTokenSortOption) sortLabelBuilder;
  final ValueChanged<String> onClientFilterChanged;
  final ValueChanged<ClientTokenStatusFilter> onStatusChanged;
  final ValueChanged<ClientTokenSortOption> onSortChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onRefresh;
  final VoidCallback onToggleAutoRefresh;
  final VoidCallback onRetryLoad;
  final bool Function(String tokenId) isRevokingToken;
  final bool Function(String tokenId) isDeletingToken;
  final bool Function(String tokenId) isCopyingTokenSecret;
  final ValueChanged<ClientTokenSummary> onViewDetails;
  final ValueChanged<ClientTokenSummary> onCopyClientToken;
  final ValueChanged<ClientTokenSummary> onEdit;
  final ValueChanged<ClientTokenSummary> onRevoke;
  final ValueChanged<ClientTokenSummary> onDelete;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClientTokenListToolbar(
          isLoading: isLoading,
          autoRefreshAfterCreate: autoRefreshAfterCreate,
          isListInteractionLocked: isListInteractionLocked,
          onRefresh: onRefresh,
          onToggleAutoRefresh: onToggleAutoRefresh,
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsSectionTitle(
          title: l10n.ctSectionRegisteredTokens,
        ),
        const SizedBox(height: AppSpacing.sm),
        ClientTokenListFilters(
          clientFilterController: clientFilterController,
          tokenStatusFilter: tokenStatusFilter,
          tokenSortOption: tokenSortOption,
          isEnabled: !isListInteractionLocked,
          onClientFilterChanged: onClientFilterChanged,
          statusLabelBuilder: statusLabelBuilder,
          sortLabelBuilder: sortLabelBuilder,
          onStatusChanged: onStatusChanged,
          onSortChanged: onSortChanged,
          onClearFilters: onClearFilters,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isInitialLoading)
          const SizedBox(
            height: 160,
            child: Center(
              child: ProgressRing(),
            ),
          ),
        if (!hasLoaded && hasLoadError)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: l10n.btnRetry,
              isPrimary: false,
              icon: FluentIcons.refresh,
              onPressed: onRetryLoad,
            ),
          ),
        if (hasLoaded && listedTokens.isEmpty && !isLoading)
          Text(
            hasActiveFilters ? l10n.ctMsgNoTokenMatchFilter : l10n.ctMsgNoTokenFound,
          ),
        if (listedTokens.isNotEmpty)
          SizedBox(
            height: 440,
            child: ClientTokenSummaryGrid(
              tokens: listedTokens,
              scrollController: scrollController,
              isRevokingToken: isRevokingToken,
              isDeletingToken: isDeletingToken,
              isCopyingTokenSecret: isCopyingTokenSecret,
              actionsEnabled: !isListInteractionLocked,
              onViewDetails: onViewDetails,
              onCopyClientToken: onCopyClientToken,
              onEdit: onEdit,
              onRevoke: onRevoke,
              onDelete: onDelete,
            ),
          ),
      ],
    );
  }
}
