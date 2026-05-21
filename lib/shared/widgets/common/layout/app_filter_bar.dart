import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    required this.children,
    super.key,
    this.spacing = AppSpacing.sm,
    this.runSpacing = AppSpacing.sm,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: children,
    );
  }
}
