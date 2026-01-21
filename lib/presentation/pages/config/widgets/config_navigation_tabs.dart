import 'package:fluent_ui/fluent_ui.dart';

import '../../../../core/theme/app_colors.dart';

class ConfigNavigationTabs extends StatelessWidget {
  const ConfigNavigationTabs({
    super.key,
    required this.currentPage,
    required this.onDatabaseTabTap,
    required this.onWebSocketTabTap,
  });

  final int currentPage;
  final VoidCallback onDatabaseTabTap;
  final VoidCallback onWebSocketTabTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Configuração do Banco de Dados',
              icon: FluentIcons.database,
              isSelected: currentPage == 0,
              onTap: onDatabaseTabTap,
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Conexão WebSocket',
              icon: FluentIcons.plug_connected,
              isSelected: currentPage == 1,
              onTap: onWebSocketTabTap,
            ),
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
    final backgroundColor = isSelected ? AppColors.primary : Colors.transparent;
    final textColor = isSelected ? Colors.white : theme.resources.textFillColorPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
