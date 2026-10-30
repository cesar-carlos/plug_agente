import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions/action_io_output_preview_controller.dart';
import 'package:provider/provider.dart';

class AgentActionIoOutputPreview extends StatelessWidget {
  const AgentActionIoOutputPreview({required this.output, required this.executionId, super.key});
  final IActionIoLocalOutput output;
  final String executionId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    key: ValueKey(executionId),
    create: (_) => ActionIoOutputPreviewController(output, executionId: executionId),
    child: Consumer<ActionIoOutputPreviewController>(
      builder: (context, preview, _) {
        final l10n = AppLocalizations.of(context)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.agentActionsIoPreviewNotice),
            Button(
              onPressed: preview.isLoading ? null : () => unawaited(preview.loadNext()),
              child: Text(l10n.agentActionsIoNextPage),
            ),
            if (preview.isLoading) const ProgressRing(),
            if (preview.errorCode != null) Text(l10n.agentActionsDiagnosticsOutputLoadFailed),
            if (preview.hasLoaded && preview.stdoutText.isEmpty && preview.stderrText.isEmpty)
              Text(preview.terminal ? l10n.agentActionsIoEmptyPage : l10n.agentActionsIoPendingOutput),
            if (preview.stdoutText.isNotEmpty) ...[
              Text(l10n.agentActionsDiagnosticsStdout),
              SelectableText(preview.stdoutText),
            ],
            if (preview.stderrText.isNotEmpty) ...[
              Text(l10n.agentActionsDiagnosticsStderr),
              SelectableText(preview.stderrText),
            ],
          ],
        );
      },
    ),
  );
}
