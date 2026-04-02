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
    this.isDestructive = false,
    this.isLoadingSemanticsLabelSuffix = ', loading',
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.semanticsLabel,
    this.labelStyle,
    this.filledBackgroundColor,
    this.filledForegroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isPrimary;

  /// When [isPrimary] is true and [filledBackgroundColor] is null, uses [AppColors.error].
  final bool isDestructive;

  /// Appended to [label] in semantics when [isLoading] is true (screen readers).
  final String isLoadingSemanticsLabelSuffix;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;
  final String? semanticsLabel;

  /// Overrides default `bodyText` + w600 for the label (and icon row text).
  final TextStyle? labelStyle;

  /// Overrides the filled primary background; wins over [isDestructive].
  final Color? filledBackgroundColor;
  final Color? filledForegroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = FluentTheme.of(context);
    final baseTextStyle = labelStyle ?? context.bodyText.copyWith(fontWeight: FontWeight.w600);

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
              Icon(icon, size: 16, color: baseTextStyle.color),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: baseTextStyle),
            ],
          )
        : Text(label, style: baseTextStyle);

    final effectiveOnPressed = isLoading ? null : onPressed;
    final effectiveSemanticsLabel = semanticsLabel ?? (isLoading ? '$label$isLoadingSemanticsLabelSuffix' : label);

    Widget button = isPrimary
        ? FilledButton(
            focusNode: focusNode,
            autofocus: autofocus,
            style: _primaryFilledStyle(colors),
            onPressed: effectiveOnPressed,
            child: child,
          )
        : Button(
            focusNode: focusNode,
            autofocus: autofocus,
            style: _secondaryStyle(theme),
            onPressed: effectiveOnPressed,
            child: child,
          );

    if (tooltip != null && tooltip!.trim().isNotEmpty) {
      button = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: button,
      );
    }

    return Semantics(
      button: true,
      enabled: effectiveOnPressed != null,
      label: effectiveSemanticsLabel,
      excludeSemantics: true,
      child: button,
    );
  }

  ButtonStyle _secondaryStyle(FluentThemeData theme) {
    return ButtonStyle(
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
    );
  }

  ButtonStyle _primaryFilledStyle(AppThemeColors colors) {
    var style = ButtonStyle(
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
    );

    final bg = filledBackgroundColor ?? (isDestructive ? colors.error : null);
    final fg =
        filledForegroundColor ?? (isDestructive && filledBackgroundColor == null ? const Color(0xFFFFFFFF) : null);

    if (bg != null || fg != null) {
      final merged = style.merge(
        ButtonStyle(
          backgroundColor: bg != null ? WidgetStateProperty.all(bg) : null,
          foregroundColor: fg != null ? WidgetStateProperty.all(fg) : null,
        ),
      );
      if (merged != null) {
        style = merged;
      }
    }

    return style;
  }
}
