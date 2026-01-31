import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/shared/widgets/common/action_button.dart';
import 'package:plug_agente/shared/widgets/common/app_button.dart';

class FilterButton extends StatelessWidget {
  const FilterButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.isSelected = false,
    this.count,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isSelected;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final displayLabel = count != null ? '$label $count' : label;

    if (isSelected) {
      return AppButton(
        label: displayLabel,
        icon: icon,
        onPressed: onPressed,
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
