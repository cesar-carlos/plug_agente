import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket_config_section.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:provider/provider.dart';

class WebSocketSettingsPage extends StatefulWidget {
  const WebSocketSettingsPage({
    this.configId,
    super.key,
  });

  final String? configId;

  @override
  State<WebSocketSettingsPage> createState() => _WebSocketSettingsPageState();
}

class _WebSocketSettingsPageState extends State<WebSocketSettingsPage> {
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
      if (widget.configId != null) {
        _loadConfig(widget.configId!);
      }
      _checkAndInitializeFields();
      _setupAuthListener();
      _setupConnectionListener();
      _setupConfigListener();
    });
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  void _setupAuthListener() {
    _authProvider = context.read<AuthProvider>();
    _previousAuthStatus = _authProvider!.status;
    _previousAuthError = _authProvider!.error;
    _authProvider!.addListener(_onAuthStateChanged);
  }

  void _setupConnectionListener() {
    _connectionProvider = context.read<ConnectionProvider>();
    _previousConnectionStatus = _connectionProvider!.status;
    _previousConnectionError = _connectionProvider!.error;
    _connectionProvider!.addListener(_onConnectionStateChanged);
  }

  void _setupConfigListener() {
    _configProvider = context.read<ConfigProvider>();
    _previousConfigError = _configProvider!.error;
    _configProvider!.addListener(_onConfigStateChanged);
  }

  void _onAuthStateChanged() {
    if (!mounted) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
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
    if (!mounted) {
      return;
    }

    final connectionProvider = context.read<ConnectionProvider>();
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
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
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
        final connectionProvider = context.read<ConnectionProvider>();
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
        final configProvider = context.read<ConfigProvider>();
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
        final authProvider = context.read<AuthProvider>();
        authProvider.clearError();
      },
    );
  }

  void _checkAndInitializeFields() {
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
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

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          AppStrings.navWebSocketSettings,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          maxWidth: AppLayout.maxSettingsWidth,
          child: WebSocketConfigSection(
            formController: _formController,
            configProvider: configProvider,
            onSaveConfig: () {
              _formController.updateAllFieldsToProvider(configProvider);
              configProvider.saveConfig();
            },
          ),
        ),
      ),
    );
  }
}
