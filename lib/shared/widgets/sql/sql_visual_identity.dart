import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';

class SqlVisualIdentity {
  SqlVisualIdentity._();

  static const EdgeInsets panelPadding = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets editorPanelPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.sm,
  );
  static const BorderRadius panelBorderRadius = BorderRadius.all(
    Radius.circular(AppRadius.sm),
  );

  /// Compact grid for query results (Syncfusion defaults: 49 / 56).
  static const double queryResultDataGridRowHeight = 30;
  static const double queryResultDataGridHeaderRowHeight = 34;
  static const EdgeInsets queryResultDataGridCellPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: 2,
  );
  static const EdgeInsets queryResultDataGridHeaderPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xs,
  );
}
