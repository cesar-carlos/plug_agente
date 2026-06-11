import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_row_actions.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_ui_formatters.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_data_grid.dart';

List<AppGridColumn> clientTokenGridColumns(AppLocalizations l10n) => [
  AppGridColumn(label: l10n.ctLabelClient, flex: 3),
  AppGridColumn(label: l10n.ctLabelId, flex: 4),
  AppGridColumn(label: l10n.ctLabelStatus, flex: 2),
  AppGridColumn(label: l10n.ctLabelScope, flex: 2),
  AppGridColumn(
    label: l10n.ctLabelCreatedAt,
    flex: 3,
    alignment: Alignment.center,
  ),
  AppGridColumn(
    label: l10n.ctGridColumnActions,
    flex: 4,
    alignment: Alignment.center,
  ),
];

class ClientTokenSummaryGrid extends StatelessWidget {
  const ClientTokenSummaryGrid({
    required this.tokens,
    required this.isRevokingToken,
    required this.isDeletingToken,
    required this.isCopyingTokenSecret,
    required this.actionsEnabled,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onRevoke,
    required this.onDelete,
    this.scrollController,
    super.key,
  });

  final List<ClientTokenSummary> tokens;
  final ScrollController? scrollController;
  final bool Function(String tokenId) isRevokingToken;
  final bool Function(String tokenId) isDeletingToken;
  final bool Function(String tokenId) isCopyingTokenSecret;
  final bool actionsEnabled;
  final ValueChanged<ClientTokenSummary> onViewDetails;
  final ValueChanged<ClientTokenSummary> onCopyClientToken;
  final ValueChanged<ClientTokenSummary> onEdit;
  final ValueChanged<ClientTokenSummary> onRevoke;
  final ValueChanged<ClientTokenSummary> onDelete;

  String _buildPermissionsLabel(
    ClientPermissionSet permissions,
    AppLocalizations l10n,
  ) {
    final labels = <String>[
      if (permissions.canRead) l10n.ctPermissionRead,
      if (permissions.canUpdate) l10n.ctPermissionUpdate,
      if (permissions.canDelete) l10n.ctPermissionDelete,
      if (permissions.canDdl) l10n.ctPermissionDdl,
    ];
    return labels.join(', ');
  }

  String _buildScopeLabel(ClientTokenSummary token, AppLocalizations l10n) {
    if (token.allPermissions) return l10n.ctScopeAllPermissions;
    final scopes = <String>[
      if (token.allTables) l10n.ctScopeTables,
      if (token.allViews) l10n.ctScopeViews,
    ];
    if (scopes.isEmpty) {
      return l10n.ctScopeRestricted;
    }

    final permissionsLabel = _buildPermissionsLabel(
      token.globalPermissions,
      l10n,
    );
    if (permissionsLabel.isEmpty) {
      return scopes.join(', ');
    }
    return '${scopes.join(', ')}: $permissionsLabel';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppDataGridScrollable<ClientTokenSummary>(
      columns: clientTokenGridColumns(l10n),
      rows: tokens,
      scrollController: scrollController,
      rowCells: (token) => [
        Tooltip(
          message: token.name.isNotEmpty ? token.clientId : '',
          child: SelectableText(token.name.isNotEmpty ? token.name : token.clientId),
        ),
        SelectableText(token.id),
        Text(
          token.isRevoked ? l10n.ctStatusRevoked : l10n.ctStatusActive,
        ),
        Text(_buildScopeLabel(token, l10n)),
        Text(
          formatClientTokenDateTime(context, token.createdAt),
        ),
        ClientTokenRowActions(
          l10n: l10n,
          token: token,
          isRevoking: isRevokingToken(token.id),
          isDeleting: isDeletingToken(token.id),
          isCopyingTokenSecret: isCopyingTokenSecret(token.id),
          actionsEnabled: actionsEnabled,
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
