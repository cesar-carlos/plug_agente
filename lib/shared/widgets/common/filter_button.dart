import 'package:fluent_ui/fluent_ui.dart';

import 'app_button.dart';
import 'action_button.dart';

class FilterButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isSelected;
  final String? count;

  const FilterButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isSelected = false,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final displayLabel = count != null ? '$label $count' : label;
    
    if (isSelected) {
      return AppButton(
        label: displayLabel,
        icon: icon,
        onPressed: onPressed,
        isPrimary: true,
      );
    }
    
    return ActionButton(
      label: displayLabel,
      icon: icon,
      onPressed: onPressed,
      iconSize: 14,
    );
  }
}
