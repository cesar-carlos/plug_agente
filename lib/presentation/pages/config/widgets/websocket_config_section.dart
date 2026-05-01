import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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
                onLoginOrLogout: () => unawaited(_handleLoginOrLogout(context)),
              ),
              const SizedBox(height: 24),
              const _OutboundCompressionSection(),
              const SizedBox(height: 24),
              const _ClientTokenPolicyIntrospectionSection(),
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

  Future<void> _handleLoginOrLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.isAuthenticated) {
      await Provider.of<ConnectionProvider>(context, listen: false).disconnect();
      await authProvider.logout(clearStoredSession: true);
    } else {
      final serverUrl = normalizeServerUrl(
        formController.serverUrlController.text,
      );
      if (serverUrl.isEmpty) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgServerUrlRequired,
        );
        return;
      }
      final agentId = formController.agentIdController.text.trim();
      if (agentId.isEmpty) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: l10n.msgAgentIdRequired,
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
          title: l10n.modalTitleError,
          message: l10n.msgAuthCredentialsRequired,
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
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
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
                    const SizedBox(height: 16),
                    AppTextField(
                      label: l10n.wsFieldAgentId,
                      controller: formController.agentIdController,
                      hint: l10n.wsHintAgentId,
                      readOnly: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: formController.authPasswordController,
                      hint: l10n.wsHintPassword,
                    ),
                    const SizedBox(height: 16),
                    Consumer<ConnectionProvider>(
                      builder: (context, connectionProvider, _) {
                        final isAuthenticating = authProvider.status == AuthStatus.authenticating;
                        final isConnectionBusy =
                            connectionProvider.status == ConnectionStatus.connecting ||
                            connectionProvider.isReconnecting;
                        final canSubmit = authProvider.isAuthenticated || (!isAuthenticating && !isConnectionBusy);
                        return AppButton(
                          label: isAuthenticating
                              ? l10n.wsButtonAuthenticating
                              : authProvider.isAuthenticated
                              ? l10n.wsButtonLogout
                              : l10n.wsButtonLogin,
                          isPrimary: false,
                          isLoading: isAuthenticating,
                          onPressed: canSubmit ? onLoginOrLogout : null,
                        );
                      },
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

class _ClientTokenPolicyIntrospectionSection extends StatefulWidget {
  const _ClientTokenPolicyIntrospectionSection();

  @override
  State<_ClientTokenPolicyIntrospectionSection> createState() => _ClientTokenPolicyIntrospectionSectionState();
}

class _ClientTokenPolicyIntrospectionSectionState extends State<_ClientTokenPolicyIntrospectionSection> {
  late final FeatureFlags _flags = getIt<FeatureFlags>();
  late bool _introspectionEnabled;

  @override
  void initState() {
    super.initState();
    _introspectionEnabled = _flags.enableClientTokenPolicyIntrospection;
  }

  Future<void> _onChanged(bool enabled) async {
    setState(() => _introspectionEnabled = enabled);
    await _flags.setEnableClientTokenPolicyIntrospection(enabled);
    if (mounted) {
      setState(() => _introspectionEnabled = _flags.enableClientTokenPolicyIntrospection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      child: SettingsSectionBlock(
        title: l10n.wsSectionClientTokenPolicy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToggleSwitch(
              checked: _introspectionEnabled,
              onChanged: (bool value) => unawaited(_onChanged(value)),
              content: Text(l10n.wsFieldClientTokenPolicyIntrospection),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsClientTokenPolicyIntrospectionDescription,
              style: context.captionText,
            ),
          ],
        ),
      ),
    );
  }
}

class _OutboundCompressionSection extends StatefulWidget {
  const _OutboundCompressionSection();

  @override
  State<_OutboundCompressionSection> createState() => _OutboundCompressionSectionState();
}

class _OutboundCompressionSectionState extends State<_OutboundCompressionSection> {
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
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      child: SettingsSectionBlock(
        title: l10n.wsSectionOutboundCompression,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<OutboundCompressionMode>(
              label: l10n.wsFieldOutboundCompressionMode,
              value: _mode,
              items: [
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.none,
                  child: Text(l10n.wsOutboundCompressionOff),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.gzip,
                  child: Text(l10n.wsOutboundCompressionGzip),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.auto,
                  child: Text(l10n.wsOutboundCompressionAuto),
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
              l10n.wsOutboundCompressionDescription,
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
    final l10n = AppLocalizations.of(context)!;
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, _) {
        return Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            final isConnecting = connectionProvider.status == ConnectionStatus.connecting;
            final isReconnecting = connectionProvider.status == ConnectionStatus.reconnecting;
            final isConnectionBusy = isConnecting || isReconnecting;
            return SettingsActionRow(
              leading: AppButton(
                label: connectionProvider.isConnected ? l10n.wsButtonDisconnect : l10n.wsButtonConnect,
                isLoading: isConnectionBusy,
                onPressed: () => _handleConnectOrDisconnect(
                  context,
                  connectionProvider,
                  authProvider,
                ),
              ),
              trailing: AppButton(
                label: l10n.wsButtonSaveConfig,
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
    if (connectionProvider.status == ConnectionStatus.connecting ||
        connectionProvider.status == ConnectionStatus.reconnecting) {
      return;
    }
    if (connectionProvider.isConnected) {
      connectionProvider.disconnect();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final serverUrl = normalizeServerUrl(
      formController.serverUrlController.text,
    );
    final agentId = formController.agentIdController.text.trim();
    if (serverUrl.isEmpty || agentId.isEmpty) {
      return;
    }
    final authToken = authProvider.currentToken?.token.trim();
    if (!authProvider.isAuthenticated || authToken == null || authToken.isEmpty) {
      SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: l10n.msgLoginRequiredBeforeConnect,
      );
      return;
    }
    configProvider.updateServerUrl(serverUrl);
    configProvider.updateAgentId(agentId);
    connectionProvider.connect(serverUrl, agentId, authToken: authToken);
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return const ConnectionStatusWidget();
  }
}
