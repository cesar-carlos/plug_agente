import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_form_shared.dart';

class ClientTokenCreateDialogPolicySection extends StatelessWidget {
  const ClientTokenCreateDialogPolicySection({
    required this.allTables,
    required this.allViews,
    required this.globalCanRead,
    required this.globalCanUpdate,
    required this.globalCanDelete,
    required this.globalCanDdl,
    required this.onToggleAllTables,
    required this.onToggleAllViews,
    required this.onToggleGlobalRead,
    required this.onToggleGlobalUpdate,
    required this.onToggleGlobalDelete,
    required this.onToggleGlobalDdl,
    super.key,
  });

  final bool allTables;
  final bool allViews;
  final bool globalCanRead;
  final bool globalCanUpdate;
  final bool globalCanDelete;
  final bool globalCanDdl;
  final ValueChanged<bool> onToggleAllTables;
  final ValueChanged<bool> onToggleAllViews;
  final ValueChanged<bool> onToggleGlobalRead;
  final ValueChanged<bool> onToggleGlobalUpdate;
  final ValueChanged<bool> onToggleGlobalDelete;
  final ValueChanged<bool> onToggleGlobalDdl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        ClientTokenFlagCheckbox(
          focusOrder: 5,
          label: l10n.ctFlagAllTables,
          value: allTables,
          onChanged: onToggleAllTables,
        ),
        ClientTokenFlagCheckbox(
          focusOrder: 6,
          label: l10n.ctFlagAllViews,
          value: allViews,
          onChanged: onToggleAllViews,
        ),
        ClientTokenFlagCheckbox(
          focusOrder: 7,
          label: l10n.ctPermissionRead,
          value: globalCanRead,
          onChanged: onToggleGlobalRead,
        ),
        ClientTokenFlagCheckbox(
          focusOrder: 8,
          label: l10n.ctPermissionUpdate,
          value: globalCanUpdate,
          onChanged: onToggleGlobalUpdate,
        ),
        ClientTokenFlagCheckbox(
          focusOrder: 9,
          label: l10n.ctPermissionDelete,
          value: globalCanDelete,
          onChanged: onToggleGlobalDelete,
        ),
        ClientTokenFlagCheckbox(
          focusOrder: 10,
          label: l10n.ctPermissionDdl,
          value: globalCanDdl,
          onChanged: onToggleGlobalDdl,
        ),
      ],
    );
  }
}
