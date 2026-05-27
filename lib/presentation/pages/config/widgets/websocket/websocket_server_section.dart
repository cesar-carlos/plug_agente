import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket/websocket_config_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/form/password_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

/// View-model exposed to [Selector3]. Records compare structurally so the
/// section only rebuilds when one of these fields actually changes.
typedef WebSocketServerVm = ({
  bool isAuthenticatedForConfig,
  bool isAuthenticating,
  bool isConnectionBusy,
  bool isConnected,
  bool isWaitingForHub,
});

class WebSocketServerSection extends StatelessWidget {
  const WebSocketServerSection({
    required this.formController,
    required this.controller,
    super.key,
  });

  final ConfigFormController formController;
  final WebSocketConfigController controller;

  @override
  Widget build(BuildContext context) {
    return Selector3<AuthProvider, ConnectionProvider, ConfigProvider, WebSocketServerVm>(
      selector: (_, auth, connection, config) {
        final currentConfigId = config.currentConfig?.id;
        final isAuthenticatedForConfig = auth.isAuthenticatedForConfig(currentConfigId);
        final isAuthenticating = auth.status == AuthStatus.authenticating;
        final isConnectionBusy =
            connection.status == ConnectionStatus.connecting ||
            connection.status == ConnectionStatus.negotiating ||
            connection.isReconnecting;
        final isWaitingForHub =
            isAuthenticatedForConfig &&
            !connection.isConnected &&
            (connection.isReconnecting ||
                connection.status == ConnectionStatus.connecting ||
                connection.status == ConnectionStatus.negotiating);
        return (
          isAuthenticatedForConfig: isAuthenticatedForConfig,
          isAuthenticating: isAuthenticating,
          isConnectionBusy: isConnectionBusy,
          isConnected: connection.isConnected,
          isWaitingForHub: isWaitingForHub,
        );
      },
      builder: (context, vm, _) {
        return _ServerCard(
          formController: formController,
          vm: vm,
          onLoginOrLogout: () => _handleLoginOrLogout(context),
        );
      },
    );
  }

  Future<void> _handleLoginOrLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final outcome = await controller.loginOrLogout();
    if (!context.mounted) {
      return;
    }
    switch (outcome) {
      case WebSocketActionSuccess():
      case WebSocketActionAlreadyBusy():
        return;
      case WebSocketActionMissingServerUrl():
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgServerUrlRequired,
        );
      case WebSocketActionMissingAgentId():
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgAgentIdRequired,
        );
      case WebSocketActionMissingCredentials():
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgAuthCredentialsRequired,
        );
      case WebSocketActionSaveFailed(:final failure):
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleErrorSaving,
          message: failure.toDisplayMessage(),
        );
      case WebSocketActionLoginRequired():
        return;
    }
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.formController,
    required this.vm,
    required this.onLoginOrLogout,
  });

  final ConfigFormController formController;
  final WebSocketServerVm vm;
  final Future<void> Function() onLoginOrLogout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSubmit = vm.isAuthenticatedForConfig || (!vm.isAuthenticating && !vm.isConnectionBusy);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionBlock(
            title: l10n.wsSectionConnection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: l10n.wsFieldServerUrl,
                  controller: formController.serverUrlController,
                  hint: l10n.wsHintServerUrl,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.wsFieldAgentId,
                  controller: formController.agentIdController,
                  hint: l10n.wsHintAgentId,
                  readOnly: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsSectionBlock(
            title: l10n.wsSectionOptionalAuth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: l10n.wsFieldUsername,
                  controller: formController.authUsernameController,
                  hint: l10n.wsHintUsername,
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordField(
                  controller: formController.authPasswordController,
                  hint: l10n.wsHintPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: vm.isAuthenticating
                      ? l10n.wsButtonAuthenticating
                      : vm.isAuthenticatedForConfig
                      ? l10n.wsButtonLogout
                      : l10n.wsButtonLogin,
                  isPrimary: false,
                  isLoading: vm.isAuthenticating,
                  onPressed: canSubmit ? () => unawaited(onLoginOrLogout()) : null,
                ),
                if (vm.isWaitingForHub) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.wsSubtitleSessionWaitingForHub,
                    style: context.captionText,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
