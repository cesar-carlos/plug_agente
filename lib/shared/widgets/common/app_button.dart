import 'package:fluent_ui/fluent_ui.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isPrimary;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: ProgressRing(strokeWidth: 2),
          )
        : icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Text(label),
            ],
          )
        : Text(label);

    final effectiveOnPressed = isLoading ? null : onPressed;

    if (isPrimary) {
      return FilledButton(onPressed: effectiveOnPressed, child: child);
    }

    return Button(onPressed: effectiveOnPressed, child: child);
  }
}
