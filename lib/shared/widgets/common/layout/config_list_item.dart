import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/theme/theme.dart';

class ConfigListItem extends StatelessWidget {
  const ConfigListItem({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isSelected = false,
  });
  final String title;
  final String? subtitle;
  final String? trailing;
  final void Function()? onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? colors.selectedFill : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.bodyStrong.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected ? colors.selectedForeground : colors.textPrimary,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: context.bodyMuted.copyWith(
                color: isSelected ? colors.selectedForeground : colors.textSecondary,
              ),
            ),
          if (trailing != null)
            Text(
              trailing!,
              style: context.bodyMuted.copyWith(
                color: isSelected ? colors.selectedForeground : colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
