import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/theme/theme.dart';

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
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          _TabButton(
            label: 'Geral',
            icon: FluentIcons.settings,
            isSelected: currentPage == 0,
            onTap: onGeneralTabTap,
          ),
          _TabSeparator(color: theme.resources.controlStrokeColorDefault),
          _TabButton(
            label: 'WebSocket',
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
    final theme = FluentTheme.of(context);
    final backgroundColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.2)
        : Colors.transparent;
    final textColor = isSelected
        ? AppColors.primary
        : theme.resources.textFillColorPrimary;

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
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
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
  const _TabSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: AppSpacing.md + 2,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
      color: color.withValues(alpha: 0.4),
    );
  }
}
