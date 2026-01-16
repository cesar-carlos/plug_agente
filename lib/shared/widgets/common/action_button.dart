import 'package:fluent_ui/fluent_ui.dart';

class ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isDestructive;
  final double? iconSize;

  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isDestructive = false,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    const destructiveColor = Color(0xFFD13438);

    if (isLoading) {
      return Button(
        onPressed: null,
        child: const SizedBox(
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

    return Button(
      onPressed: onPressed,
      style: buttonStyle,
      child: Text(label),
    );
  }
}

