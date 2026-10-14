import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

/// Gives Fluent checkbox content finite space so long labels can wrap.
///
/// The indicator size and gap match [Checkbox] in fluent_ui (20px box, 8px gap).
/// Theme padding and margin are added so the reserve follows the control instead
/// of a fixed leftover width.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({required this.checked, required this.content, this.onChanged, super.key});

  static const double _indicatorExtent = 20;
  static const double _labelGap = 8;

  final bool checked;
  final Widget content;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = CheckboxTheme.of(context);
    final direction = Directionality.of(context);
    final reserved =
        _indicatorExtent +
        _labelGap +
        (style.padding?.resolve(direction).horizontal ?? 0) +
        (style.margin?.resolve(direction).horizontal ?? 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final labelMaxWidth = maxWidth.isFinite ? math.max(0, maxWidth - reserved).toDouble() : null;
        return Checkbox(
          checked: checked,
          onChanged: onChanged,
          content: labelMaxWidth == null
              ? content
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMaxWidth),
                  child: content,
                ),
        );
      },
    );
  }
}
