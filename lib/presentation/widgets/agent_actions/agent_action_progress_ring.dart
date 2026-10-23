import 'package:fluent_ui/fluent_ui.dart';

/// Keeps the long-running action animation from repainting the static row.
class AgentActionProgressRing extends StatelessWidget {
  const AgentActionProgressRing({super.key});
  @override
  Widget build(BuildContext context) => const RepaintBoundary(child: ProgressRing(strokeWidth: 2));
}
