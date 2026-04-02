import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';

class AppLayout {
  AppLayout._();

  static const double compactBreakpoint = 960;
  static const double mediumBreakpoint = 1280;
  static const double wideBreakpoint = 1600;

  static const double maxContentWidth = 1440;
  static const double maxPaneContentWidth = 1920;
  static const double maxSettingsWidth = 1320;
  static const double maxDataWidth = 1440;
  static const double maxFormWidth = 640;
  static const double maxWideFormWidth = 1120;
  static const double scrollbarPadding = 16;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= wideBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      );
    }

    if (width >= mediumBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      );
    }

    if (width >= compactBreakpoint) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      );
    }

    return const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xs,
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
