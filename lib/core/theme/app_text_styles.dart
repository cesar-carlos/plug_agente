import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/theme/app_colors.dart';

extension AppTextStyles on BuildContext {
  Typography get _typography => FluentTheme.of(this).typography;
  AppThemeColors get _colors => appColors;

  TextStyle get pageTitle =>
      _typography.titleLarge?.copyWith(
        color: _colors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ) ??
      TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: _colors.textPrimary,
      );

  TextStyle get sectionTitle =>
      _typography.subtitle?.copyWith(
        color: _colors.textPrimary,
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _colors.textPrimary,
      );

  TextStyle get bodyText =>
      _typography.body?.copyWith(
        color: _colors.textPrimary,
        fontWeight: FontWeight.w400,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: _colors.textPrimary,
      );

  TextStyle get bodyStrong =>
      _typography.bodyStrong?.copyWith(
        color: _colors.textPrimary,
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _colors.textPrimary,
      );

  TextStyle get bodyMuted => bodyText.copyWith(
    color: _colors.textSecondary,
  );

  TextStyle get captionText =>
      _typography.caption?.copyWith(
        color: _colors.textSecondary,
        fontWeight: FontWeight.w400,
      ) ??
      TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: _colors.textSecondary,
      );

  TextStyle get captionStrong => captionText.copyWith(
    color: _colors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  TextStyle get metricValue =>
      _typography.bodyStrong?.copyWith(
        color: _colors.textPrimary,
        fontWeight: FontWeight.w700,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _colors.textPrimary,
      );
}
