import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

/// Gives Fluent checkbox content finite space so long labels can wrap.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({required this.checked, required this.content, this.onChanged, super.key});
  final bool checked;
  final Widget content;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Checkbox(
      checked: checked,
      onChanged: onChanged,
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 40)),
        child: content,
      ),
    ),
  );
}
