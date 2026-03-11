import 'package:fluent_ui/fluent_ui.dart';

extension AppTextStyles on BuildContext {
  Typography get _typography => FluentTheme.of(this).typography;
  Color get _primaryText => FluentTheme.of(this).resources.textFillColorPrimary;

  TextStyle get pageTitle =>
      _typography.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ) ??
      TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: _primaryText,
      );

  TextStyle get sectionTitle =>
      _typography.subtitle?.copyWith(
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _primaryText,
      );

  TextStyle get bodyText =>
      _typography.body?.copyWith(
        fontWeight: FontWeight.w400,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: _primaryText,
      );

  TextStyle get bodyStrong =>
      _typography.bodyStrong?.copyWith(
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _primaryText,
      );

  TextStyle get bodyMuted => bodyText.copyWith(
    color: _primaryText.withValues(alpha: 0.75),
  );

  TextStyle get metricValue =>
      _typography.bodyStrong?.copyWith(
        fontWeight: FontWeight.w700,
      ) ??
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _primaryText,
      );
}
