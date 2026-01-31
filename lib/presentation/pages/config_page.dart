import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/odbc_drivers.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/config_navigation_tabs.dart';
import 'package:plug_agente/presentation/pages/config/widgets/database_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket_config_section.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/message_modal.dart';
import 'package:provider/provider.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  int _currentPage = 0;
  AuthStatus? _previousAuthStatus;
  String _previousAuthError = '';
  ConnectionStatus? _previousConnectionStatus;
  String _previousConnectionError = '';
  String _previousConfigError = '';
  AuthProvider? _authProvider;
  ConnectionProvider? _connectionProvider;
  ConfigProvider? _configProvider;
  late final ConfigFormController _formController;

  @override
  void initState() {
    super.initState();
    _formController = ConfigFormController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndInitializeFields();
      _setupAuthListener();
      _setupConnectionListener();
      _setupConfigListener();
    });
  }

  void _setupAuthListener() {
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _previousAuthStatus = _authProvider!.status;
    _previousAuthError = _authProvider!.error;
    _authProvider!.addListener(_onAuthStateChanged);
  }

  void _setupConnectionListener() {
    _connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    _previousConnectionStatus = _connectionProvider!.status;
    _previousConnectionError = _connectionProvider!.error;
    _connectionProvider!.addListener(_onConnectionStateChanged);
  }

  void _setupConfigListener() {
    _configProvider = Provider.of<ConfigProvider>(context, listen: false);
    _previousConfigError = _configProvider!.error;
    _configProvider!.addListener(_onConfigStateChanged);
  }

  void _onAuthStateChanged() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentStatus = authProvider.status;
    final currentError = authProvider.error;

    if (_previousAuthStatus != AuthStatus.authenticated &&
        currentStatus == AuthStatus.authenticated &&
        currentError.isEmpty) {
      _showSuccessModal();
    }

    if (currentError.isNotEmpty && currentError != _previousAuthError) {
      _showErrorModal(currentError);
    }

    _previousAuthStatus = currentStatus;
    _previousAuthError = currentError;
  }

  void _onConnectionStateChanged() {
    if (!mounted) return;

    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    final currentStatus = connectionProvider.status;
    final currentError = connectionProvider.error;

    if (_previousConnectionStatus != ConnectionStatus.connected &&
        currentStatus == ConnectionStatus.connected) {
      _showConnectionSuccessModal();
    }

    if (currentError.isNotEmpty && currentError != _previousConnectionError) {
      _showConnectionErrorModal(currentError);
    }

    _previousConnectionStatus = currentStatus;
    _previousConnectionError = currentError;
  }

  void _onConfigStateChanged() {
    if (!mounted) return;

    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final currentError = configProvider.error;

    if (currentError.isNotEmpty && currentError != _previousConfigError) {
      _showConfigErrorModal(currentError);
    }

    _previousConfigError = currentError;
  }

  void _showSuccessModal() {
    MessageModal.show<void>(
      context: context,
      title: 'Sucesso',
      message: 'Autenticado com sucesso!',
      type: MessageType.success,
      confirmText: 'OK',
    );
  }

  void _showConnectionSuccessModal() {
    MessageModal.show<void>(
      context: context,
      title: 'Conexão Estabelecida',
      message: 'Conectado ao servidor WebSocket com sucesso!',
      type: MessageType.success,
      confirmText: 'OK',
    );
  }

  void _showConnectionErrorModal(String error) {
    MessageModal.show<void>(
      context: context,
      title: 'Erro de Conexão',
      message: error,
      type: MessageType.error,
      confirmText: 'OK',
      onConfirm: () {
        final connectionProvider = Provider.of<ConnectionProvider>(
          context,
          listen: false,
        );
        connectionProvider.clearError();
      },
    );
  }

  void _showConfigErrorModal(String error) {
    MessageModal.show<void>(
      context: context,
      title: 'Erro de Configuração',
      message: error,
      type: MessageType.error,
      confirmText: 'OK',
      onConfirm: () {
        final configProvider = Provider.of<ConfigProvider>(
          context,
          listen: false,
        );
        configProvider.clearError();
      },
    );
  }

  void _showErrorModal(String error) {
    MessageModal.show<void>(
      context: context,
      title: 'Erro de Autenticação',
      message: error,
      type: MessageType.error,
      confirmText: 'OK',
      onConfirm: () {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.clearError();
      },
    );
  }

  void _checkAndInitializeFields() {
    if (!mounted) return;
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    if (!_formController.fieldsInitialized &&
        !configProvider.isLoading &&
        configProvider.currentConfig != null) {
      _formController.initializeFromConfig(configProvider.currentConfig);
    } else if (configProvider.isLoading) {
      Future.delayed(
        const Duration(milliseconds: 100),
        _checkAndInitializeFields,
      );
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthStateChanged);
    _connectionProvider?.removeListener(_onConnectionStateChanged);
    _configProvider?.removeListener(_onConfigStateChanged);
    _formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = context.read<ConfigProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    return ScaffoldPage(
      header: const PageHeader(title: Text('Configurações - Plug Database')),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          children: [
            ConfigNavigationTabs(
              currentPage: _currentPage,
              onDatabaseTabTap: () => setState(() => _currentPage = 0),
              onWebSocketTabTap: () => setState(() => _currentPage = 1),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _currentPage == 0
                  ? DatabaseConfigSection(
                      formController: _formController,
                      configProvider: configProvider,
                      connectionProvider: connectionProvider,
                      onDriverChanged: (value) {
                        setState(() {
                          configProvider.updateDriverName(value);
                          final currentOdbcName =
                              _formController.odbcDriverNameController.text;

                          if (OdbcDrivers.isDefaultSuggestion(
                            currentOdbcName,
                          )) {
                            final suggestion = OdbcDrivers.getDefaultDriver(
                              value,
                            );
                            if (suggestion.isNotEmpty) {
                              _formController.odbcDriverNameController.text =
                                  suggestion;
                              configProvider.updateOdbcDriverName(suggestion);
                            }
                          }
                        });
                      },
                      onTestConnection: () async {
                        final odbcDriverName = _formController
                            .odbcDriverNameController
                            .text
                            .trim();
                        if (odbcDriverName.isEmpty) {
                          MessageModal.show<void>(
                            context: context,
                            title: 'Erro',
                            message: 'Nome do Driver ODBC é obrigatório',
                            type: MessageType.error,
                            confirmText: 'OK',
                          );
                          return;
                        }

                        final driverCheckResult = await connectionProvider
                            .checkOdbcDriver(odbcDriverName);
                        await driverCheckResult.fold(
                          (isInstalled) async {
                            if (!isInstalled) {
                              MessageModal.show<void>(
                                context: context,
                                title: 'Driver Não Encontrado',
                                message:
                                    'Driver ODBC "$odbcDriverName" não foi encontrado. Verifique se o driver está instalado antes de testar a conexão.',
                                type: MessageType.error,
                                confirmText: 'OK',
                              );
                              return;
                            }

                            _formController.updateAllFieldsToProvider(
                              configProvider,
                            );
                            final connectionString = configProvider
                                .getConnectionString();
                            final testResult = await connectionProvider
                                .testDbConnection(connectionString);

                            if (!mounted) return;

                            testResult.fold(
                              (isConnected) {
                                MessageModal.show<void>(
                                  context: context,
                                  title: isConnected
                                      ? 'Conexão Bem-Sucedida'
                                      : 'Falha na Conexão',
                                  message: isConnected
                                      ? 'Conexão com o banco de dados estabelecida com sucesso!'
                                      : 'Não foi possível conectar ao banco de dados. Verifique as credenciais e configurações.',
                                  type: isConnected
                                      ? MessageType.success
                                      : MessageType.error,
                                  confirmText: 'OK',
                                );
                              },
                              (failure) {
                                final failureMessage = failure is domain.Failure
                                    ? failure.message
                                    : failure.toString();
                                MessageModal.show<void>(
                                  context: context,
                                  title: 'Erro ao Testar Conexão',
                                  message: failureMessage,
                                  type: MessageType.error,
                                  confirmText: 'OK',
                                );
                              },
                            );
                          },
                          (failure) async {
                            final failureMessage = failure is domain.Failure
                                ? failure.message
                                : failure.toString();
                            MessageModal.show<void>(
                              context: context,
                              title: 'Erro ao Verificar Driver',
                              message: failureMessage,
                              type: MessageType.error,
                              confirmText: 'OK',
                            );
                          },
                        );
                      },
                      onSaveConfig: () async {
                        final odbcDriverName = _formController
                            .odbcDriverNameController
                            .text
                            .trim();
                        if (odbcDriverName.isEmpty) {
                          MessageModal.show<void>(
                            context: context,
                            title: 'Erro',
                            message: 'Nome do Driver ODBC é obrigatório',
                            type: MessageType.error,
                            confirmText: 'OK',
                          );
                          return;
                        }

                        final driverCheckResult = await connectionProvider
                            .checkOdbcDriver(odbcDriverName);
                        await driverCheckResult.fold(
                          (isInstalled) async {
                            if (!isInstalled) {
                              MessageModal.show<void>(
                                context: context,
                                title: 'Driver Não Encontrado',
                                message:
                                    'Driver ODBC "$odbcDriverName" não foi encontrado. Verifique se o driver está instalado antes de salvar a configuração.',
                                type: MessageType.error,
                                confirmText: 'OK',
                              );
                              return;
                            }

                            _formController.updateAllFieldsToProvider(
                              configProvider,
                            );
                            final saveResult = await configProvider
                                .saveConfig();

                            if (!mounted) return;

                            saveResult.fold(
                              (_) {
                                MessageModal.show<void>(
                                  context: context,
                                  title: 'Configuração Salva',
                                  message: 'Configuração salva com sucesso!',
                                  type: MessageType.success,
                                  confirmText: 'OK',
                                );
                              },
                              (failure) {
                                final failureMessage = failure is domain.Failure
                                    ? failure.message
                                    : failure.toString();
                                MessageModal.show<void>(
                                  context: context,
                                  title: 'Erro ao Salvar',
                                  message: failureMessage,
                                  type: MessageType.error,
                                  confirmText: 'OK',
                                );
                              },
                            );
                          },
                          (failure) async {
                            final failureMessage = failure is domain.Failure
                                ? failure.message
                                : failure.toString();
                            MessageModal.show<void>(
                              context: context,
                              title: 'Erro ao Verificar Driver',
                              message: failureMessage,
                              type: MessageType.error,
                              confirmText: 'OK',
                            );
                          },
                        );
                      },
                    )
                  : WebSocketConfigSection(
                      formController: _formController,
                      configProvider: configProvider,
                      onSaveConfig: () {
                        _formController.updateAllFieldsToProvider(
                          configProvider,
                        );
                        configProvider.saveConfig();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
