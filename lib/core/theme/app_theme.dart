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
      'normal': AppColors.brand,
      'light': Color(0xFF268CDB),
      'lighter': Color(0xFF63B3ED),
      'lightest': Color(0xFF9ED5F5),
    },
  );

  static String get fontFamily =>
      GoogleFonts.montserrat().fontFamily ?? 'Montserrat';

  static final FluentThemeData _lightTheme = _buildTheme(
    brightness: Brightness.light,
  );
  static final FluentThemeData _darkTheme = _buildTheme(
    brightness: Brightness.dark,
  );

  static FluentThemeData light() => _lightTheme;

  static FluentThemeData dark() => _darkTheme;

  static FluentThemeData _buildTheme({
    required Brightness brightness,
  }) {
    final resources = brightness.isLight
        ? const ResourceDictionary.light()
        : const ResourceDictionary.dark();
    final tokens = AppThemeColors.fromTheme(
      brightness: brightness,
      accentColor: accentColor,
      resources: resources,
      cardColor: resources.cardBackgroundFillColorDefault,
    );

    return FluentThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      accentColor: accentColor,
      resources: resources,
      scaffoldBackgroundColor: resources.layerOnAcrylicFillColorDefault,
      micaBackgroundColor: resources.solidBackgroundFillColorBase,
      cardColor: resources.cardBackgroundFillColorDefault,
      selectionColor: tokens.selectedForeground,
      extensions: [tokens],
      typography: AppTypography.fromBrightness(
        brightness: brightness,
        fontFamily: fontFamily,
      ),
    );
  }
}
