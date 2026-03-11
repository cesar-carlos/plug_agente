import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';

class AppLayout {
  AppLayout._();

  static const double compactBreakpoint = 960;
  static const double mediumBreakpoint = 1280;
  static const double wideBreakpoint = 1600;

  static const double maxContentWidth = 1280;
  static const double maxSettingsWidth = 1120;
  static const double maxDataWidth = 1440;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= wideBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.md,
      );
    }

    if (width >= mediumBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      );
    }

    return const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageHorizontal,
      vertical: AppSpacing.md,
    );
  }

  static Widget centeredContent({
    required Widget child,
    double maxWidth = maxContentWidth,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
