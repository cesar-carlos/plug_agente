import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

class ClientTokenListToolbar extends StatelessWidget {
  const ClientTokenListToolbar({
    required this.isLoading,
    required this.autoRefreshAfterCreate,
    required this.isListInteractionLocked,
    required this.onRefresh,
    required this.onToggleAutoRefresh,
    super.key,
  });

  final bool isLoading;
  final bool autoRefreshAfterCreate;
  final bool isListInteractionLocked;
  final VoidCallback onRefresh;
  final VoidCallback onToggleAutoRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        AppButton(
          label: l10n.ctButtonRefreshList,
          icon: FluentIcons.refresh,
          isPrimary: false,
          isLoading: isLoading,
          onPressed: isListInteractionLocked ? null : onRefresh,
        ),
        const SizedBox(width: AppSpacing.md),
        AppButton(
          label: autoRefreshAfterCreate ? l10n.ctButtonAutoRefreshOn : l10n.ctButtonAutoRefreshOff,
          icon: autoRefreshAfterCreate ? FluentIcons.sync : FluentIcons.pause,
          isPrimary: false,
          onPressed: isListInteractionLocked ? null : onToggleAutoRefresh,
        ),
      ],
    );
  }
}
