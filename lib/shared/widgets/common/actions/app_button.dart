import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isPrimary = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final baseTextStyle = context.bodyText.copyWith(
      fontWeight: FontWeight.w600,
    );
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
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: baseTextStyle),
            ],
          )
        : Text(label, style: baseTextStyle);

    final effectiveOnPressed = isLoading ? null : onPressed;

    if (isPrimary) {
      return FilledButton(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        onPressed: effectiveOnPressed,
        child: child,
      );
    }

    return Button(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: theme.resources.controlStrokeColorDefault),
          ),
        ),
      ),
      onPressed: effectiveOnPressed,
      child: child,
    );
  }
}
