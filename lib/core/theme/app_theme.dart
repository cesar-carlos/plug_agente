import 'package:fluent_ui/fluent_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plug_agente/core/theme/app_colors.dart';
import 'package:plug_agente/core/theme/app_typography.dart';

class AppTheme {
  AppTheme._();

  static AccentColor get accentColor => AccentColor.swatch(
    const {
      'darkest': Color(0xFF003D6B),
      'darker': Color(0xFF005A9E),
      'dark': Color(0xFF006FC3),
      'normal': AppColors.primary,
      'light': Color(0xFF268CDB),
      'lighter': Color(0xFF63B3ED),
      'lightest': Color(0xFF9ED5F5),
    },
  );

  static String get fontFamily => GoogleFonts.montserrat().fontFamily ?? 'Montserrat';

  static FluentThemeData light() {
    return _buildTheme(brightness: Brightness.light);
  }

  static FluentThemeData dark() {
    return _buildTheme(brightness: Brightness.dark);
  }

  static FluentThemeData _buildTheme({
    required Brightness brightness,
  }) {
    return FluentThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      accentColor: accentColor,
      typography: AppTypography.fromBrightness(
        brightness: brightness,
        fontFamily: fontFamily,
      ),
    );
  }
}
