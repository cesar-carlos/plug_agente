import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/shared/widgets/agent_operational_readiness_strip.dart';

class WebSocketStatusSection extends StatelessWidget {
  const WebSocketStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgentOperationalReadinessStrip(),
        SizedBox(height: AppSpacing.sm),
        ConnectionStatusWidget(),
      ],
    );
  }
}
