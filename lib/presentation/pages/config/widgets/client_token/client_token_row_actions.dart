import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class ClientTokenRowActions extends StatelessWidget {
  const ClientTokenRowActions({
    required this.l10n,
    required this.token,
    required this.isRevoking,
    required this.isDeleting,
    required this.isCopyingTokenSecret,
    required this.actionsEnabled,
    required this.onViewDetails,
    required this.onCopyClientToken,
    required this.onEdit,
    required this.onDelete,
    this.onRevoke,
    super.key,
  });

  final AppLocalizations l10n;
  final ClientTokenSummary token;
  final bool isRevoking;
  final bool isDeleting;
  final bool isCopyingTokenSecret;
  final bool actionsEnabled;
  final VoidCallback onViewDetails;
  final VoidCallback onCopyClientToken;
  final VoidCallback onEdit;
  final VoidCallback? onRevoke;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final revokeTooltip = token.isRevoked ? l10n.ctButtonRevoked : l10n.ctButtonRevoke;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        Tooltip(
          message: l10n.ctTooltipEditToken,
          child: Semantics(
            button: true,
            label: l10n.ctButtonEdit,
            child: IconButton(
              icon: const Icon(FluentIcons.edit),
              onPressed: actionsEnabled ? onEdit : null,
            ),
          ),
        ),
        Tooltip(
          message: l10n.ctButtonViewDetails,
          child: Semantics(
            button: true,
            label: l10n.ctButtonViewDetails,
            child: IconButton(
              icon: const Icon(FluentIcons.view),
              onPressed: actionsEnabled ? onViewDetails : null,
            ),
          ),
        ),
        Tooltip(
          message: l10n.ctTooltipCopyClientToken,
          child: Semantics(
            button: true,
            label: l10n.ctButtonCopyClientToken,
            child: isCopyingTokenSecret
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
                    icon: const Icon(FluentIcons.copy),
                    onPressed: actionsEnabled ? onCopyClientToken : null,
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
                    onPressed: actionsEnabled ? onRevoke : null,
                  ),
          ),
        ),
        Tooltip(
          message: l10n.ctButtonDelete,
          child: Semantics(
            button: true,
            label: l10n.ctButtonDelete,
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
                    onPressed: actionsEnabled ? onDelete : null,
                  ),
          ),
        ),
      ],
    );
  }
}
