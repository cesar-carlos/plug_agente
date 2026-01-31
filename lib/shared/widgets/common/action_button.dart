import 'package:fluent_ui/fluent_ui.dart';

class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.isLoading = false,
    this.isDestructive = false,
    this.iconSize,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isDestructive;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    const destructiveColor = Color(0xFFD13438);

    if (isLoading) {
      return const Button(
        onPressed: null,
        child: SizedBox(
          width: 16,
          height: 16,
          child: ProgressRing(strokeWidth: 2),
        ),
      );
    }

    final buttonStyle = ButtonStyle(
      foregroundColor: isDestructive
          ? WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.disabled)) {
                return theme.resources.textFillColorDisabled;
              }
              return destructiveColor;
            })
          : null,
    );

    if (icon != null) {
      return Button(
        onPressed: onPressed,
        style: buttonStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize ?? 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
    }

    return Button(onPressed: onPressed, style: buttonStyle, child: Text(label));
  }
}
