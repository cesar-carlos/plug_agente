import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_colors.dart';

class ConfigListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final void Function()? onTap;
  final bool isSelected;

  const ConfigListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final textColor = theme.typography.body?.color;

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.primary : textColor,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? AppColors.primary.withValues(alpha: 0.7) : textColor?.withValues(alpha: 0.7),
              ),
            ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? AppColors.primary.withValues(alpha: 0.7) : textColor?.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}
