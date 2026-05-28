import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_config_controller.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

/// View-model exposed to [Selector]. Records compare structurally so this
/// widget only rebuilds when one of these fields changes, not on every
/// `notifyListeners` of the underlying provider.
typedef WebSocketActionButtonsVm = ({
  bool isConnectionBusy,
  bool isConnected,
});

class WebSocketActionButtons extends StatelessWidget {
  const WebSocketActionButtons({
    required this.controller,
    required this.onSaveConfig,
    required this.isSavingConfig,
    super.key,
  });

  final WebSocketConfigController controller;
  final Future<void> Function() onSaveConfig;
  final ValueListenable<bool> isSavingConfig;

  @override
  Widget build(BuildContext context) {
    return Selector<ConnectionProvider, WebSocketActionButtonsVm>(
      selector: (_, connection) {
        final status = connection.status;
        final isConnectionBusy =
            status == ConnectionStatus.connecting ||
            status == ConnectionStatus.negotiating ||
            status == ConnectionStatus.reconnecting;
        return (
          isConnectionBusy: isConnectionBusy,
          isConnected: connection.isConnected,
        );
      },
      builder: (context, vm, _) {
        final l10n = AppLocalizations.of(context)!;
        return ValueListenableBuilder<bool>(
          valueListenable: isSavingConfig,
          builder: (context, saving, _) {
            return SettingsActionRow(
              leading: AppButton(
                label: vm.isConnected ? l10n.wsButtonDisconnect : l10n.wsButtonConnect,
                isLoading: vm.isConnectionBusy,
                onPressed: (vm.isConnectionBusy || saving) ? null : () => _handleConnectOrDisconnect(context),
              ),
              trailing: AppButton(
                label: l10n.wsButtonSaveConfig,
                isLoading: saving,
                onPressed: saving ? null : onSaveConfig,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleConnectOrDisconnect(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final outcome = await controller.connectOrDisconnect();
    if (!context.mounted) {
      return;
    }
    switch (outcome) {
      case WebSocketActionSuccess():
      case WebSocketActionAlreadyBusy():
      case WebSocketActionMissingServerUrl():
      case WebSocketActionMissingAgentId():
      case WebSocketActionMissingCredentials():
        return;
      case WebSocketActionLoginRequired():
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgLoginRequiredBeforeConnect,
        );
      case WebSocketActionSaveFailed(:final failure):
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleErrorSaving,
          message: failure.toDisplayMessage(),
        );
    }
  }
}
