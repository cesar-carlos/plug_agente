import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../../domain/value_objects/auth_credentials.dart';
import '../../../../shared/widgets/common/app_button.dart';
import '../../../../shared/widgets/common/app_card.dart';
import '../../../../shared/widgets/common/app_text_field.dart';
import '../../../../shared/widgets/common/message_modal.dart';
import '../../../../shared/widgets/common/password_field.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/connection_provider.dart';
import '../../../widgets/connection_status_widget.dart';
import '../config_form_controller.dart';

class WebSocketConfigSection extends StatelessWidget {
  const WebSocketConfigSection({
    super.key,
    required this.formController,
    required this.configProvider,
    required this.onSaveConfig,
  });

  final ConfigFormController formController;
  final ConfigProvider configProvider;
  final VoidCallback onSaveConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServerSection(
              formController: formController,
              onLoginOrLogout: () => _handleLoginOrLogout(context),
            ),
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
    );
  }

  void _handleLoginOrLogout(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.isAuthenticated) {
      authProvider.logout();
    } else {
      final serverUrl = formController.serverUrlController.text.trim();
      if (serverUrl.isEmpty) {
        MessageModal.show(
          context: context,
          title: 'Erro',
          message: 'URL do Servidor é obrigatória',
          type: MessageType.error,
          confirmText: 'OK',
        );
        return;
      }

      if (formController.authUsernameController.text.isNotEmpty &&
          formController.authPasswordController.text.isNotEmpty) {
        final credentials = AuthCredentials(
          username: formController.authUsernameController.text.trim(),
          password: formController.authPasswordController.text.trim(),
        );
        authProvider.login(serverUrl, credentials);
      } else {
        MessageModal.show(
          context: context,
          title: 'Erro',
          message: 'Usuário e senha são obrigatórios',
          type: MessageType.error,
          confirmText: 'OK',
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
              Text(
                'Conexão WebSocket',
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'URL do Servidor',
                controller: formController.serverUrlController,
                hint: 'https://api.example.com',
                enabled: true,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'ID do Agente',
                controller: formController.agentIdController,
                hint: 'UUID ou Nome Único',
                enabled: true,
              ),
              const SizedBox(height: 24),
              Text(
                'Autenticação (Opcional)',
                style: FluentTheme.of(context).typography.subtitle,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Usuário',
                controller: formController.authUsernameController,
                hint: 'Usuário para autenticação',
                enabled: true,
              ),
              const SizedBox(height: 16),
              PasswordField(
                label: 'Senha',
                controller: formController.authPasswordController,
                hint: 'Senha para autenticação',
                validator: null,
                enabled: true,
              ),
              const SizedBox(height: 16),
              AppButton(
                label: authProvider.status == AuthStatus.authenticating
                    ? 'Autenticando...'
                    : authProvider.isAuthenticated
                        ? 'Logout'
                        : 'Login',
                isPrimary: false,
                isLoading: authProvider.status == AuthStatus.authenticating,
                onPressed: onLoginOrLogout,
              ),
            ],
          ),
        );
      },
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
            return Row(
              children: [
                AppButton(
                  label: connectionProvider.isConnected ? 'Desconectar' : 'Conectar',
                  isPrimary: true,
                  onPressed: () => _handleConnectOrDisconnect(
                    context,
                    connectionProvider,
                    authProvider,
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  label: 'Salvar Configuração',
                  isLoading: configProvider.isLoading,
                  onPressed: onSaveConfig,
                ),
              ],
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
      final serverUrl = formController.serverUrlController.text.trim();
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
