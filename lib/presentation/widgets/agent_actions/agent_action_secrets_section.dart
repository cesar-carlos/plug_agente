import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_secret_dialog.dart';

class AgentActionSecretsSection extends StatelessWidget {
  const AgentActionSecretsSection({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final secretNames = provider.selectedSecretPlaceholderNames.toList()..sort();
    if (!provider.isActionSecretStoreAvailable || secretNames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.agentActionsSecretsSectionTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.agentActionsSecretsSectionMessage,
          style: FluentTheme.of(context).typography.body,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final secretName in secretNames)
          _AgentActionSecretRow(
            key: ValueKey<String>('agent_action_secret_row_$secretName'),
            secretName: secretName,
            provider: provider,
            l10n: l10n,
            isConfigured: provider.isActionSecretConfigured(secretName),
            isSaving: provider.isSavingActionSecret(secretName),
            isDeleting: provider.isDeletingActionSecret(secretName),
          ),
      ],
    );
  }
}

class _AgentActionSecretRow extends StatelessWidget {
  const _AgentActionSecretRow({
    required this.secretName,
    required this.provider,
    required this.l10n,
    required this.isConfigured,
    required this.isSaving,
    required this.isDeleting,
    super.key,
  });

  final String secretName;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final bool isConfigured;
  final bool isSaving;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final isBusy = isSaving || isDeleting;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secretName,
                      style: FluentTheme.of(context).typography.bodyStrong,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _SecretStatusBadge(
                      label: isConfigured
                          ? l10n.agentActionsSecretStatusConfigured
                          : l10n.agentActionsSecretStatusMissing,
                      isConfigured: isConfigured,
                    ),
                  ],
                ),
              ),
              Button(
                key: ValueKey<String>('agent_action_secret_configure_button_$secretName'),
                onPressed: isBusy
                    ? null
                    : () {
                        unawaited(
                          showAgentActionSecretConfigureDialog(
                            context: context,
                            l10n: l10n,
                            secretName: secretName,
                            onSave: (value) => provider.saveActionSecret(
                              secretName: secretName,
                              secretValue: value,
                            ),
                          ),
                        );
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : Text(
                        isConfigured ? l10n.agentActionsSecretUpdate : l10n.agentActionsSecretConfigure,
                      ),
              ),
              if (isConfigured) ...[
                const SizedBox(width: AppSpacing.sm),
                Button(
                  key: ValueKey<String>('agent_action_secret_remove_button_$secretName'),
                  onPressed: isBusy
                      ? null
                      : () async {
                          final confirmed = await confirmDeleteAgentActionSecret(
                            context: context,
                            l10n: l10n,
                            secretName: secretName,
                          );
                          if (!confirmed || !context.mounted) {
                            return;
                          }
                          await provider.deleteActionSecret(secretName);
                        },
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Text(l10n.agentActionsSecretRemove),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SecretStatusBadge extends StatelessWidget {
  const _SecretStatusBadge({
    required this.label,
    required this.isConfigured,
  });

  final String label;
  final bool isConfigured;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = isConfigured ? theme.accentColor : const Color(0xFFC50F1F);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: theme.typography.caption?.copyWith(color: color),
        ),
      ),
    );
  }
}
