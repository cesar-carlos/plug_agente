import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class AgentActionIdCopyButton extends StatelessWidget {
  const AgentActionIdCopyButton({
    required this.actionId,
    required this.l10n,
    required this.placement,
    this.tooltip,
    this.copiedMessage,
    this.dense = false,
    super.key,
  });

  final String actionId;
  final AppLocalizations l10n;
  final String placement;
  final String? tooltip;
  final String? copiedMessage;

  /// Shrinks the hit target so the icon stays on a caption line.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final label = tooltip ?? l10n.agentActionsCopyActionId;
    return Tooltip(
      message: label,
      child: IconButton(
        key: ValueKey<String>('agent_action_${placement}_copy_id_$actionId'),
        icon: Icon(
          FluentIcons.copy,
          size: 12,
          semanticLabel: label,
        ),
        iconButtonMode: IconButtonMode.tiny,
        style: dense
            ? const ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              )
            : null,
        onPressed: () {
          unawaited(
            copyAgentActionId(
              context,
              l10n,
              actionId,
              copiedMessage: copiedMessage,
            ),
          );
        },
      ),
    );
  }
}

Future<void> copyAgentActionId(
  BuildContext context,
  AppLocalizations l10n,
  String actionId, {
  String? copiedMessage,
}) async {
  await Clipboard.setData(ClipboardData(text: actionId));
  if (!context.mounted) {
    return;
  }
  displayInfoBar(
    context,
    builder: (context, close) {
      return InfoBar(
        title: Text(copiedMessage ?? l10n.agentActionsActionIdCopied),
        severity: InfoBarSeverity.success,
        onClose: close,
      );
    },
  );
}
