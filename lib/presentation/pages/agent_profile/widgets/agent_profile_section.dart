import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Visual scaffolding for a labeled section of the agent profile form.
///
/// Each section renders its [title] followed by [child], keeping spacing
/// consistent across Identity, Contact, Address and Notes blocks.
class AgentProfileSection extends StatelessWidget {
  const AgentProfileSection({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}
