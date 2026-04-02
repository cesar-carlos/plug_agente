import 'package:fluent_ui/fluent_ui.dart';

enum AppFeedbackTone { info, success, warning, error }

class AppFeedbackColors {
  const AppFeedbackColors({
    required this.accent,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color accent;
  final Color foreground;
  final Color background;
  final Color border;
}

class AppColors {
  AppColors._();

  static const Color brand = Color(0xFF0078D4);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFD13438);
}

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.brand,
    required this.success,
    required this.warning,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.disabled,
    required this.surfaceCard,
    required this.surfaceSubtle,
    required this.border,
    required this.selectedFill,
    required this.selectedForeground,
    required this.brightness,
  });

  factory AppThemeColors.fromTheme({
    required Brightness brightness,
    required AccentColor accentColor,
    required ResourceDictionary resources,
    required Color cardColor,
  }) {
    final brand = accentColor.normal;
    final selectedFillOpacity = brightness.isDark ? 0.22 : 0.12;

    return AppThemeColors(
      brand: brand,
      success: AppColors.success,
      warning: AppColors.warning,
      error: AppColors.error,
      textPrimary: resources.textFillColorPrimary,
      textSecondary: resources.textFillColorSecondary,
      disabled: resources.textFillColorSecondary,
      surfaceCard: cardColor,
      surfaceSubtle: resources.subtleFillColorSecondary,
      border: resources.controlStrokeColorDefault,
      selectedFill: brand.withValues(alpha: selectedFillOpacity),
      selectedForeground: brand,
      brightness: brightness,
    );
  }

  final Color brand;
  final Color success;
  final Color warning;
  final Color error;
  final Color textPrimary;
  final Color textSecondary;
  final Color disabled;
  final Color surfaceCard;
  final Color surfaceSubtle;
  final Color border;
  final Color selectedFill;
  final Color selectedForeground;
  final Brightness brightness;

  AppFeedbackColors feedback(AppFeedbackTone tone) {
    final accent = switch (tone) {
      AppFeedbackTone.info => brand,
      AppFeedbackTone.success => success,
      AppFeedbackTone.warning => warning,
      AppFeedbackTone.error => error,
    };
    final backgroundOpacity = brightness.isDark ? 0.18 : 0.08;
    final borderOpacity = brightness.isDark ? 0.4 : 0.25;

    return AppFeedbackColors(
      accent: accent,
      foreground: tone == AppFeedbackTone.error ? accent : textPrimary,
      background: Color.alphaBlend(
        accent.withValues(alpha: backgroundOpacity),
        surfaceCard,
      ),
      border: accent.withValues(alpha: borderOpacity),
    );
  }

  @override
  AppThemeColors copyWith({
    Color? brand,
    Color? success,
    Color? warning,
    Color? error,
    Color? textPrimary,
    Color? textSecondary,
    Color? disabled,
    Color? surfaceCard,
    Color? surfaceSubtle,
    Color? border,
    Color? selectedFill,
    Color? selectedForeground,
    Brightness? brightness,
  }) {
    return AppThemeColors(
      brand: brand ?? this.brand,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      disabled: disabled ?? this.disabled,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      border: border ?? this.border,
      selectedFill: selectedFill ?? this.selectedFill,
      selectedForeground: selectedForeground ?? this.selectedForeground,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  AppThemeColors lerp(
    covariant ThemeExtension<AppThemeColors>? other,
    double t,
  ) {
    if (other is! AppThemeColors) {
      return this;
    }

    return AppThemeColors(
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      disabled: Color.lerp(disabled, other.disabled, t) ?? disabled,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t) ?? surfaceCard,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t) ?? surfaceSubtle,
      border: Color.lerp(border, other.border, t) ?? border,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t) ?? selectedFill,
      selectedForeground: Color.lerp(selectedForeground, other.selectedForeground, t) ?? selectedForeground,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors {
    final theme = FluentTheme.of(this);
    return theme.extension<AppThemeColors>() ??
        AppThemeColors.fromTheme(
          brightness: theme.brightness,
          accentColor: theme.accentColor,
          resources: theme.resources,
          cardColor: theme.cardColor,
        );
  }
}
