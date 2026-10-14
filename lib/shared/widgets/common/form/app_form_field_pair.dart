import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AppFormFieldPair extends StatelessWidget {
  const AppFormFieldPair({
    required this.first,
    required this.second,
    this.breakpoint = AppLayout.formFieldRowBreakpoint,
    super.key,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (AppLayout.formFieldsStack(context, constraints.maxWidth, breakpoint: breakpoint)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            const SizedBox(height: AppSpacing.sm),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: second),
        ],
      );
    },
  );
}
