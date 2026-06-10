import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

abstract final class AgentActionEditorLayout {
  AgentActionEditorLayout._();

  static const int dialogSectionCount = 6;

  static const double _contentHorizontal = AppSpacing.md;

  /// Symmetric content inset with extra right gutter for the scrollbar track.
  static const EdgeInsets dialogScrollPadding = EdgeInsets.fromLTRB(
    _contentHorizontal,
    0,
    _contentHorizontal + AppLayout.scrollbarPadding,
    AppSpacing.md,
  );

  static const EdgeInsets dialogFooterPadding = EdgeInsets.fromLTRB(
    _contentHorizontal,
    AppSpacing.sm,
    _contentHorizontal + AppLayout.scrollbarPadding,
    0,
  );

  static Widget build({
    required bool showChrome,
    required ScrollController scrollController,
    required Widget form,
    required Widget saveButton,
  }) {
    if (showChrome) {
      return form;
    }

    return Column(
      children: [
        Expanded(
          child: PrimaryScrollController.none(
            child: Scrollbar(
              controller: scrollController,
              child: ListView(
                controller: scrollController,
                primary: false,
                padding: dialogScrollPadding,
                children: [
                  form,
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: dialogFooterPadding,
          child: saveButton,
        ),
      ],
    );
  }
}
