import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_id_copy_button.dart';

class AgentActionCopyableIdentifier extends StatelessWidget {
  const AgentActionCopyableIdentifier({
    required this.value,
    required this.label,
    required this.placement,
    required this.l10n,
    required this.copyTooltip,
    required this.copiedMessage,
    this.compact = false,
    super.key,
  });

  final String value;
  final String label;
  final String placement;
  final AppLocalizations l10n;
  final String copyTooltip;
  final String copiedMessage;

  /// Keeps the value beside the copy icon instead of stretching a fake field.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _compact(context);
    final resources = FluentTheme.of(context).resources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.captionStrong),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: resources.controlFillColorSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: resources.controlStrokeColorDefault),
                ),
                child: SelectableText(value, style: context.captionText),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: copyTooltip,
              child: Button(
                key: ValueKey<String>('agent_action_${placement}_copy_id_$value'),
                onPressed: () {
                  unawaited(
                    copyAgentActionId(
                      context,
                      l10n,
                      value,
                      copiedMessage: copiedMessage,
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.copy, size: 12),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l10n.agentActionsCopy),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.captionStrong),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Flexible(
              child: SelectableText(
                value,
                style: context.captionText.copyWith(
                  fontFamily: 'Cascadia Mono',
                  fontFamilyFallback: const ['Consolas', 'monospace'],
                ),
              ),
            ),
            AgentActionIdCopyButton(
              actionId: value,
              l10n: l10n,
              placement: placement,
              tooltip: copyTooltip,
              copiedMessage: copiedMessage,
            ),
          ],
        ),
      ],
    );
  }
}
