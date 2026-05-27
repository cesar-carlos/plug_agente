import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

const double _compactBreakpoint = 640;

/// Lays out [children] in a [Row] with optional flex weights on wide widths
/// and stacks them vertically when the available width is too narrow for
/// side-by-side fields.
class ResponsiveFieldRow extends StatelessWidget {
  const ResponsiveFieldRow({
    required this.children,
    super.key,
    this.flexes,
  });

  final List<Widget> children;
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactBreakpoint) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(
                flex: flexes?[index] ?? 1,
                child: children[index],
              ),
              if (index < children.length - 1) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

/// Pairs a primary form [field] with a secondary [action] button on the
/// right; stacks them and right-aligns the action on narrow widths.
class ResponsiveFieldActionRow extends StatelessWidget {
  const ResponsiveFieldActionRow({
    required this.field,
    required this.action,
    super.key,
  });

  final Widget field;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: action,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 3, child: field),
            const SizedBox(width: AppSpacing.md),
            action,
          ],
        );
      },
    );
  }
}
