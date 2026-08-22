import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

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
    this.onRunSelected,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final VoidCallback? onCreateAction;

  /// Called when the user taps "Run selected". Callers are responsible for
  /// routing through the dangerous-command check before executing.
  final VoidCallback? onRunSelected;

  @override
  Widget build(BuildContext context) {
    final blockingLabel = provider.isRunning ? l10n.agentActionsStatusRunning : null;

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
          _ToolbarButtonGroup(
            children: [
              _ToolbarCommandButton(
                icon: FluentIcons.add,
                label: l10n.agentActionsFormNew,
                onPressed: onCreateAction,
                filled: true,
                disabledReason: onCreateAction == null && !provider.isFeatureEnabled
                    ? l10n.agentActionsDisabledMessage
                    : null,
              ),
              _ToolbarCommandButton(
                icon: FluentIcons.refresh,
                label: l10n.agentActionsRefresh,
                onPressed: provider.isLoading || provider.hasBlockingLocalOperation ? null : provider.load,
                disabledReason: provider.hasBlockingLocalOperation ? blockingLabel : null,
              ),
            ],
          ),
          const _ToolbarGroupDivider(),
          _ToolbarButtonGroup(
            children: [
              _ToolbarCommandButton(
                icon: FluentIcons.download,
                label: l10n.agentActionsExportBundle,
                onPressed: provider.canTransferBundle ? () => unawaited(_exportBundle(context)) : null,
                isBusy: provider.isTransferringBundle,
                disabledReason: provider.isRunning || provider.isTesting ? blockingLabel : null,
              ),
              _ToolbarCommandButton(
                icon: FluentIcons.upload,
                label: l10n.agentActionsImportBundle,
                onPressed: provider.canTransferBundle ? () => unawaited(_importBundle(context)) : null,
                disabledReason: provider.hasBlockingLocalOperation ? blockingLabel : null,
              ),
            ],
          ),
          const _ToolbarGroupDivider(),
          _ToolbarButtonGroup(
            children: [
              _ToolbarCommandButton(
                icon: FluentIcons.play,
                label: l10n.agentActionsRunSelected,
                onPressed: provider.canRunSelected ? (onRunSelected ?? provider.runSelectedAction) : null,
                isBusy: provider.isRunning,
                disabledReason: provider.isTesting || provider.isTransferringBundle ? blockingLabel : null,
              ),
              _ToolbarCommandButton(
                icon: FluentIcons.test_beaker,
                label: l10n.agentActionsTestSelected,
                onPressed: provider.canTestSelected ? provider.testSelectedAction : null,
                isBusy: provider.isTesting,
                disabledReason: provider.isRunning || provider.isTransferringBundle ? blockingLabel : null,
              ),
            ],
          ),
          if (provider.hasLiveQueueActivity)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.processing, size: 16, color: FluentTheme.of(context).accentColor),
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
          ToggleSwitch(
            checked: provider.isMaintenanceMode,
            onChanged: provider.isFeatureEnabled
                ? (value) {
                    unawaited(_setMaintenanceMode(context, value));
                  }
                : null,
            content: Text(l10n.agentActionsMaintenanceMode),
          ),
          if (provider.isMaintenanceMode)
            Checkbox(
              checked: provider.isMaintenanceStrictMode,
              onChanged: provider.isFeatureEnabled
                  ? (value) {
                      if (value == null) {
                        return;
                      }
                      unawaited(_setMaintenanceStrictMode(context, value));
                    }
                  : null,
              content: Text(l10n.agentActionsMaintenanceStrictMode),
            ),
        ],
      ),
    );
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

    try {
      await provider.setMaintenanceMode(enabled: enabled);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'agent actions maintenance mode toggle failed',
        name: 'agent_actions_toolbar_card',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.agentActionsErrorTitle,
          message: l10n.agentActionsErrorTitle,
        );
      }
    }
  }

  Future<void> _setMaintenanceStrictMode(BuildContext context, bool enabled) async {
    try {
      await provider.setMaintenanceStrictMode(enabled: enabled);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'agent actions maintenance strict mode toggle failed',
        name: 'agent_actions_toolbar_card',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.agentActionsErrorTitle,
          message: l10n.agentActionsErrorTitle,
        );
      }
    }
  }

  Future<void> _exportBundle(BuildContext context) async {
    try {
      final outcome = await provider.exportBundlePayload(l10n: l10n);
      if (!context.mounted) {
        return;
      }
      final payload = outcome.payload;
      if (payload == null) {
        final message = outcome.errorMessage ?? provider.errorMessage;
        if (message != null && message.isNotEmpty) {
          await SettingsFeedback.showError(
            context: context,
            title: l10n.agentActionsBundleTransferFailedTitle,
            message: message,
          );
        }
        return;
      }

      final saved = await FilePicker.saveFile(
        dialogTitle: l10n.agentActionsExportBundle,
        fileName: l10n.agentActionsExportBundleDefaultFileName,
        bytes: Uint8List.fromList(utf8.encode(payload)),
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (saved == null || !context.mounted) {
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
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: l10n.agentActionsImportBundle,
      );
      if (picked == null || !context.mounted) {
        return;
      }
      final path = picked.path;
      if (path == null || !context.mounted) {
        return;
      }

      final summary = await provider.importBundleFromFile(path, l10n: l10n);
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

const double _toolbarIconSize = 16;

class _ToolbarButtonGroup extends StatelessWidget {
  const _ToolbarButtonGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          children[index],
        ],
      ],
    );
  }
}

class _ToolbarGroupDivider extends StatelessWidget {
  const _ToolbarGroupDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      color: FluentTheme.of(context).resources.controlStrokeColorDefault,
    );
  }
}

class _ToolbarCommandButton extends StatelessWidget {
  const _ToolbarCommandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.isBusy = false,
    this.disabledReason,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool isBusy;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: _toolbarIconSize),
        const SizedBox(width: AppSpacing.xs),
        Text(label),
      ],
    );
    final button = filled
        ? FilledButton(onPressed: onPressed, child: child)
        : Button(onPressed: onPressed, child: child);

    Widget command = button;
    if (disabledReason != null && onPressed == null) {
      command = Tooltip(message: disabledReason, child: command);
    }

    if (!isBusy) {
      return command;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        command,
        const SizedBox(width: AppSpacing.xs),
        const SizedBox.square(
          dimension: _toolbarIconSize,
          child: ProgressRing(strokeWidth: 2),
        ),
      ],
    );
  }
}
