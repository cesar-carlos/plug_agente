import 'dart:async';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsToolbarCard extends StatelessWidget {
  const AgentActionsToolbarCard({
    required this.provider,
    required this.l10n,
    this.onCreateAction,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final VoidCallback? onCreateAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ..._buildActionControls(context),
          ToggleSwitch(
            checked: provider.isMaintenanceMode,
            onChanged: provider.isFeatureEnabled
                ? (value) {
                    unawaited(_setMaintenanceMode(context, value));
                  }
                : null,
            content: Text(l10n.agentActionsMaintenanceMode),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionControls(BuildContext context) {
    return [
      FilledButton(
        onPressed: onCreateAction,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.add),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsFormNew),
          ],
        ),
      ),
      Button(
        onPressed: provider.isLoading ? null : provider.load,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.refresh),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsRefresh),
          ],
        ),
      ),
      Button(
        onPressed: provider.canTransferBundle ? () => unawaited(_exportBundle(context)) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isTransferringBundle)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.download),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsExportBundle),
          ],
        ),
      ),
      Button(
        onPressed: provider.canTransferBundle ? () => unawaited(_importBundle(context)) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.upload),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsImportBundle),
          ],
        ),
      ),
      Button(
        onPressed: provider.canRunSelected ? provider.runSelectedAction : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isRunning)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.play),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsRunSelected),
          ],
        ),
      ),
      Button(
        onPressed: provider.canTestSelected ? provider.testSelectedAction : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isTesting)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.test_beaker),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsTestSelected),
          ],
        ),
      ),
      if (provider.hasLiveQueueActivity)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.processing, size: 14, color: FluentTheme.of(context).accentColor),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.agentActionsQueueActiveIndicator(
                provider.liveQueuePendingCount,
                provider.liveQueueRunningCount,
              ),
              style: context.captionText,
            ),
          ],
        ),
    ];
  }

  Future<void> _setMaintenanceMode(BuildContext context, bool enabled) async {
    if (enabled) {
      final confirmed = await MessageModal.show<bool>(
        context: context,
        title: l10n.agentActionsMaintenanceModeInfoTitle,
        message: l10n.agentActionsMaintenanceModeInfoMessage,
        type: MessageType.confirmation,
        confirmText: l10n.agentActionsMaintenanceMode,
        cancelText: l10n.btnCancel,
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
    }

    await provider.setMaintenanceMode(enabled: enabled);
  }

  Future<void> _exportBundle(BuildContext context) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.agentActionsExportBundle,
        fileName: l10n.agentActionsExportBundleDefaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null || !context.mounted) {
        return;
      }

      final ok = await provider.exportBundleToFile(path);
      if (!context.mounted) {
        return;
      }

      if (!ok) {
        final message = provider.errorMessage;
        if (message != null && message.isNotEmpty) {
          await SettingsFeedback.showError(
            context: context,
            title: l10n.agentActionsBundleTransferFailedTitle,
            message: message,
          );
        }
        return;
      }

      await SettingsFeedback.showSuccess(
        context: context,
        title: l10n.agentActionsExportBundleSuccessTitle,
        message: l10n.agentActionsExportBundleSuccessMessage,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'agent actions bundle export failed',
        name: 'agent_actions_toolbar_card',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.agentActionsBundleTransferFailedTitle,
          message: l10n.agentActionsBundlePickerError,
        );
      }
    }
  }

  Future<void> _importBundle(BuildContext context) async {
    final confirmed = await confirmImportAgentActionsBundle(context: context, l10n: l10n);
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: l10n.agentActionsImportBundle,
      );
      final path = picked?.files.singleOrNull?.path;
      if (path == null || !context.mounted) {
        return;
      }

      final summary = await provider.importBundleFromFile(path);
      if (!context.mounted) {
        return;
      }

      if (summary == null) {
        final message = provider.errorMessage;
        if (message != null && message.isNotEmpty) {
          await SettingsFeedback.showError(
            context: context,
            title: l10n.agentActionsBundleTransferFailedTitle,
            message: message,
          );
        }
        return;
      }

      var successMessage = l10n.agentActionsImportBundleSuccessMessage(
        summary.importedDefinitionIds.length,
        summary.importedTriggerIds.length,
      );
      if (summary.secretPlaceholderNames.isNotEmpty) {
        successMessage =
            '$successMessage\n\n${l10n.agentActionsImportBundleSecretsMessage(summary.secretPlaceholderNames.join(', '))}';
      }

      await SettingsFeedback.showSuccess(
        context: context,
        title: l10n.agentActionsImportBundleSuccessTitle,
        message: successMessage,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'agent actions bundle import failed',
        name: 'agent_actions_toolbar_card',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.agentActionsBundleTransferFailedTitle,
          message: l10n.agentActionsBundlePickerError,
        );
      }
    }
  }
}
