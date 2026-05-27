import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_config_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

/// View-model exposed to [Selector3]. Records compare structurally so this
/// widget only rebuilds when one of these fields changes, not on every
/// `notifyListeners` of the underlying providers.
typedef WebSocketActionButtonsVm = ({
  bool isConnectionBusy,
  bool isConnected,
  bool isSaving,
});

class WebSocketActionButtons extends StatelessWidget {
  const WebSocketActionButtons({
    required this.controller,
    required this.onSaveConfig,
    super.key,
  });

  final WebSocketConfigController controller;
  final Future<void> Function() onSaveConfig;

  @override
  Widget build(BuildContext context) {
    return Selector3<AuthProvider, ConnectionProvider, ConfigProvider, WebSocketActionButtonsVm>(
      selector: (_, _, connection, config) {
        final status = connection.status;
        final isConnectionBusy =
            status == ConnectionStatus.connecting ||
            status == ConnectionStatus.negotiating ||
            status == ConnectionStatus.reconnecting;
        return (
          isConnectionBusy: isConnectionBusy,
          isConnected: connection.isConnected,
          isSaving: config.isLoading,
        );
      },
      builder: (context, vm, _) {
        final l10n = AppLocalizations.of(context)!;
        return SettingsActionRow(
          leading: AppButton(
            label: vm.isConnected ? l10n.wsButtonDisconnect : l10n.wsButtonConnect,
            isLoading: vm.isConnectionBusy,
            onPressed: (vm.isConnectionBusy || vm.isSaving)
                ? null
                : () => _handleConnectOrDisconnect(context),
          ),
          trailing: AppButton(
            label: l10n.wsButtonSaveConfig,
            isLoading: vm.isSaving,
            onPressed: vm.isSaving ? null : onSaveConfig,
          ),
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
