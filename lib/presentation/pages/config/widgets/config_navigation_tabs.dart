import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class ConfigNavigationTabs extends StatelessWidget {
  const ConfigNavigationTabs({
    required this.currentPage,
    required this.onGeneralTabTap,
    required this.onWebSocketTabTap,
    super.key,
  });

  final int currentPage;
  final VoidCallback onGeneralTabTap;
  final VoidCallback onWebSocketTabTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          _TabButton(
            label: l10n.configTabGeneral,
            icon: FluentIcons.settings,
            isSelected: currentPage == 0,
            onTap: onGeneralTabTap,
          ),
          const _TabSeparator(),
          _TabButton(
            label: l10n.configTabWebSocket,
            icon: FluentIcons.plug_connected,
            isSelected: currentPage == 1,
            onTap: onWebSocketTabTap,
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final backgroundColor = isSelected ? colors.selectedFill : Colors.transparent;
    final textColor = isSelected ? colors.selectedForeground : colors.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.bodyText.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabSeparator extends StatelessWidget {
  const _TabSeparator();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 1,
      height: AppSpacing.md + 2,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
      color: colors.border.withValues(alpha: 0.4),
    );
  }
}
