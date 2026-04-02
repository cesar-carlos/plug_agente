import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/form/password_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class WebSocketConfigSection extends StatelessWidget {
  const WebSocketConfigSection({
    required this.formController,
    required this.configProvider,
    required this.onSaveConfig,
    super.key,
  });

  final ConfigFormController formController;
  final ConfigProvider configProvider;
  final VoidCallback onSaveConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServerSection(
                formController: formController,
                onLoginOrLogout: () => _handleLoginOrLogout(context),
              ),
              const SizedBox(height: 24),
              const _OutboundCompressionSection(),
              const SizedBox(height: 24),
              _WebSocketActionButtons(
                formController: formController,
                configProvider: configProvider,
                onSaveConfig: onSaveConfig,
              ),
              const SizedBox(height: 16),
              const _StatusSection(),
            ],
          ),
        ),
      ),
    );
  }

  void _handleLoginOrLogout(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.isAuthenticated) {
      authProvider.logout();
    } else {
      final serverUrl = normalizeServerUrl(
        formController.serverUrlController.text,
      );
      if (serverUrl.isEmpty) {
        SettingsFeedback.showError(
          context: context,
          title: AppStrings.modalTitleError,
          message: AppStrings.msgServerUrlRequired,
        );
        return;
      }
      final agentId = formController.agentIdController.text.trim();
      if (agentId.isEmpty) {
        SettingsFeedback.showError(
          context: context,
          title: AppStrings.modalTitleError,
          message: AppStrings.msgAgentIdRequired,
        );
        return;
      }

      if (formController.authUsernameController.text.isNotEmpty &&
          formController.authPasswordController.text.isNotEmpty) {
        final credentials = AuthCredentials(
          username: formController.authUsernameController.text.trim(),
          password: formController.authPasswordController.text.trim(),
          agentId: agentId,
        );
        authProvider.login(serverUrl, credentials);
      } else {
        SettingsFeedback.showError(
          context: context,
          title: AppStrings.modalTitleError,
          message: AppStrings.msgAuthCredentialsRequired,
        );
      }
    }
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({
    required this.formController,
    required this.onLoginOrLogout,
  });

  final ConfigFormController formController;
  final VoidCallback onLoginOrLogout;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSectionBlock(
                title: AppStrings.wsSectionConnection,
                child: Column(
                  children: [
                    AppTextField(
                      label: AppStrings.wsFieldServerUrl,
                      controller: formController.serverUrlController,
                      hint: AppStrings.wsHintServerUrl,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: AppStrings.wsFieldAgentId,
                      controller: formController.agentIdController,
                      hint: AppStrings.wsHintAgentId,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SettingsSectionBlock(
                title: AppStrings.wsSectionOptionalAuth,
                child: Column(
                  children: [
                    AppTextField(
                      label: AppStrings.wsFieldUsername,
                      controller: formController.authUsernameController,
                      hint: AppStrings.wsHintUsername,
                    ),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: formController.authPasswordController,
                      hint: AppStrings.wsHintPassword,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: authProvider.status == AuthStatus.authenticating
                          ? AppStrings.wsButtonAuthenticating
                          : authProvider.isAuthenticated
                          ? AppStrings.wsButtonLogout
                          : AppStrings.wsButtonLogin,
                      isPrimary: false,
                      isLoading:
                          authProvider.status == AuthStatus.authenticating,
                      onPressed: onLoginOrLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OutboundCompressionSection extends StatefulWidget {
  const _OutboundCompressionSection();

  @override
  State<_OutboundCompressionSection> createState() =>
      _OutboundCompressionSectionState();
}

class _OutboundCompressionSectionState
    extends State<_OutboundCompressionSection> {
  late final FeatureFlags _flags = getIt<FeatureFlags>();
  late OutboundCompressionMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = _flags.outboundCompressionMode;
  }

  Future<void> _onModeChanged(OutboundCompressionMode mode) async {
    setState(() => _mode = mode);
    await _flags.setOutboundCompressionMode(mode);
    if (mounted) {
      setState(() {
        _mode = _flags.outboundCompressionMode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SettingsSectionBlock(
        title: AppStrings.wsSectionOutboundCompression,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<OutboundCompressionMode>(
              label: AppStrings.wsFieldOutboundCompressionMode,
              value: _mode,
              items: const [
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.none,
                  child: Text(AppStrings.wsOutboundCompressionOff),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.gzip,
                  child: Text(AppStrings.wsOutboundCompressionGzip),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.auto,
                  child: Text(AppStrings.wsOutboundCompressionAuto),
                ),
              ],
              onChanged: (OutboundCompressionMode? value) {
                if (value != null) {
                  unawaited(_onModeChanged(value));
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.wsOutboundCompressionDescription,
              style: context.captionText,
            ),
          ],
        ),
      ),
    );
  }
}

class _WebSocketActionButtons extends StatelessWidget {
  const _WebSocketActionButtons({
    required this.formController,
    required this.configProvider,
    required this.onSaveConfig,
  });

  final ConfigFormController formController;
  final ConfigProvider configProvider;
  final VoidCallback onSaveConfig;

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, _) {
        return Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            return SettingsActionRow(
              leading: AppButton(
                label: connectionProvider.isConnected
                    ? AppStrings.wsButtonDisconnect
                    : AppStrings.wsButtonConnect,
                onPressed: () => _handleConnectOrDisconnect(
                  context,
                  connectionProvider,
                  authProvider,
                ),
              ),
              trailing: AppButton(
                label: AppStrings.wsButtonSaveConfig,
                isLoading: configProvider.isLoading,
                onPressed: onSaveConfig,
              ),
            );
          },
        );
      },
    );
  }

  void _handleConnectOrDisconnect(
    BuildContext context,
    ConnectionProvider connectionProvider,
    AuthProvider authProvider,
  ) {
    if (connectionProvider.isConnected) {
      connectionProvider.disconnect();
    } else {
      final serverUrl = normalizeServerUrl(
        formController.serverUrlController.text,
      );
      final agentId = formController.agentIdController.text.trim();
      final authToken = authProvider.currentToken?.token;

      if (serverUrl.isNotEmpty && agentId.isNotEmpty) {
        configProvider.updateServerUrl(serverUrl);
        configProvider.updateAgentId(agentId);
        connectionProvider.connect(serverUrl, agentId, authToken: authToken);
      }
    }
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return const ConnectionStatusWidget();
  }
}
