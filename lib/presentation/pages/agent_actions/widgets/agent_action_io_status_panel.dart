import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/action_io_execution_status.dart';
import 'package:plug_agente/domain/actions/action_io_lifecycle.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class AgentActionIoStatusPanel extends StatelessWidget {
  const AgentActionIoStatusPanel({required this.status, super.key});

  final ActionIoExecutionStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsIoProcessState(status.processState)),
        Text(l10n.agentActionsIoInputState(status.stdinState)),
        Text(l10n.agentActionsIoCaptureState(status.captureState)),
        Text(
          l10n.agentActionsIoByteCounts(
            status.admittedInputBytes,
            status.confirmedInputBytes,
            status.stdoutBytes,
            status.stderrBytes,
          ),
        ),
        if (status.outputExpired) Text(l10n.agentActionsIoOutputExpired),
        if (status.lifecycle.pid != null) SelectableText(l10n.agentActionsIoPid(status.lifecycle.pid!)),
        for (final stage in ActionIoMilestone.values)
          if (status.lifecycle.times[stage] != null)
            Text(l10n.agentActionsIoMilestone(stage.name, status.lifecycle.times[stage]!.toLocal().toIso8601String())),
        for (final blocker in status.lifecycle.blockers)
          SelectableText(l10n.agentActionsIoBlocker(blocker.executionId, blocker.elapsedMs ~/ 1000)),
      ],
    );
  }
}
