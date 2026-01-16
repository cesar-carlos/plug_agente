import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/value_objects/auth_credentials.dart';
import '../../domain/value_objects/database_driver.dart';
import '../../shared/widgets/common/app_button.dart';
import '../../shared/widgets/common/app_card.dart';
import '../../shared/widgets/common/app_dropdown.dart';
import '../../shared/widgets/common/app_text_field.dart';
import '../../shared/widgets/common/message_modal.dart';
import '../../shared/widgets/common/numeric_field.dart';
import '../../shared/widgets/common/password_field.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/connection_status_widget.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  // _formKey removido pois não estamos usando Form com TextFormFields
  int _currentPage = 0;
  bool _fieldsInitialized = false;
  AuthStatus? _previousAuthStatus;
  String _previousAuthError = '';
  ConnectionStatus? _previousConnectionStatus;
  String _previousConnectionError = '';
  String _previousConfigError = '';
  AuthProvider? _authProvider;
  ConnectionProvider? _connectionProvider;
  ConfigProvider? _configProvider;
  final _serverUrlController = TextEditingController();
  final _agentIdController = TextEditingController();
  final _authUsernameController = TextEditingController();
  final _authPasswordController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _databaseNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
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
    _connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
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
    
    // Verificar se houve mudança de status para autenticado
    if (_previousAuthStatus != AuthStatus.authenticated && 
        currentStatus == AuthStatus.authenticated &&
        currentError.isEmpty) {
      _showSuccessModal();
    }
    
    // Verificar se houve novo erro
    if (currentError.isNotEmpty && currentError != _previousAuthError) {
      _showErrorModal(currentError);
    }
    
    _previousAuthStatus = currentStatus;
    _previousAuthError = currentError;
  }

  void _onConnectionStateChanged() {
    if (!mounted) return;
    
    final connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
    final currentStatus = connectionProvider.status;
    final currentError = connectionProvider.error;
    
    // Verificar se houve mudança de status para conectado
    if (_previousConnectionStatus != ConnectionStatus.connected && 
        currentStatus == ConnectionStatus.connected) {
      _showConnectionSuccessModal();
    }
    
    // Verificar se houve novo erro
    if (currentError.isNotEmpty && currentError != _previousConnectionError) {
      _showConnectionErrorModal(currentError);
    }
    
    _previousConnectionStatus = currentStatus;
    _previousConnectionError = currentError;
  }

  void _showSuccessModal() {
    MessageModal.show(
      context: context,
      title: 'Sucesso',
      message: 'Autenticado com sucesso!',
      type: MessageType.success,
      confirmText: 'OK',
    );
  }

  void _showConnectionSuccessModal() {
    MessageModal.show(
      context: context,
      title: 'Conexão Estabelecida',
      message: 'Conectado ao servidor WebSocket com sucesso!',
      type: MessageType.success,
      confirmText: 'OK',
    );
  }

  void _onConfigStateChanged() {
    if (!mounted) return;
    
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final currentError = configProvider.error;
    
    // Verificar se houve novo erro
    if (currentError.isNotEmpty && currentError != _previousConfigError) {
      _showConfigErrorModal(currentError);
    }
    
    _previousConfigError = currentError;
  }

  void _showConnectionErrorModal(String error) {
    MessageModal.show(
      context: context,
      title: 'Erro de Conexão',
      message: error,
      type: MessageType.error,
      confirmText: 'OK',
      onConfirm: () {
        final connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
        connectionProvider.clearError();
      },
    );
  }

  void _showConfigErrorModal(String error) {
    MessageModal.show(
      context: context,
      title: 'Erro de Configuração',
      message: error,
      type: MessageType.error,
      confirmText: 'OK',
      onConfirm: () {
        final configProvider = Provider.of<ConfigProvider>(context, listen: false);
        configProvider.clearError();
      },
    );
  }

  void _showErrorModal(String error) {
    MessageModal.show(
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
    if (!_fieldsInitialized && !configProvider.isLoading && configProvider.currentConfig != null) {
      _initializeFields(configProvider);
    } else if (configProvider.isLoading) {
      // Se ainda estiver carregando, agendar nova verificação
      Future.delayed(const Duration(milliseconds: 100), _checkAndInitializeFields);
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthStateChanged);
    _connectionProvider?.removeListener(_onConnectionStateChanged);
    _configProvider?.removeListener(_onConfigStateChanged);
    
    _serverUrlController.dispose();
    _agentIdController.dispose();
    _authUsernameController.dispose();
    _authPasswordController.dispose();
    _driverNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseNameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _initializeFields(ConfigProvider configProvider) {
    if (_fieldsInitialized) return;

    final config = configProvider.currentConfig;

    if (config != null) {
      if (_serverUrlController.text.isEmpty) {
        _serverUrlController.text = config.serverUrl;
      }
      if (_agentIdController.text.isEmpty) {
        _agentIdController.text = config.agentId;
      }
      if (_authUsernameController.text.isEmpty) {
        _authUsernameController.text = config.authUsername ?? '';
      }
      if (_authPasswordController.text.isEmpty) {
        _authPasswordController.text = config.authPassword ?? '';
      }
      if (_driverNameController.text.isEmpty) {
        _driverNameController.text = config.driverName;
      }
      if (_usernameController.text.isEmpty) {
        _usernameController.text = config.username;
      }
      if (_passwordController.text.isEmpty) {
        _passwordController.text = config.password ?? '';
      }
      if (_databaseNameController.text.isEmpty) {
        _databaseNameController.text = config.databaseName;
      }
      if (_hostController.text.isEmpty) {
        _hostController.text = config.host;
      }
      if (_portController.text.isEmpty) {
        _portController.text = config.port.toString();
      }
      
      // Mark as initialized only if we actually had a config to load
      // This prevents "loading" empty state from marking as initialized
      _fieldsInitialized = true;
    } else {
       // If config is null, maybe we are still loading or need defaults.
       // We'll wait for config to be non-null.
    }
  }


  @override
  Widget build(BuildContext context) {
    // Apenas leitura, sem escutar mudanças para evitar rebuilds da página inteira
    final configProvider = context.read<ConfigProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    return ScaffoldPage(
      header: const PageHeader(title: Text('Configurações - Plug Database')),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          children: [
            _buildNavigationTabs(context),
            const SizedBox(height: 16),
            Expanded(
              // Usando Builder para isolar o contexto, mas evitando Consumers globais que rebuildam a tela toda
              // Os campos mantêm seu estado via TextEditingControllers
              child: _currentPage == 0
                  ? _buildDatabaseConfigPage(context, configProvider, connectionProvider)
                  : _buildWebSocketConfigPage(context, configProvider, connectionProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseConfigPage(
    BuildContext context,
    ConfigProvider configProvider,
    ConnectionProvider connectionProvider,
  ) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDatabaseSectionHeader(context),
            const SizedBox(height: 16),
            _buildDriverSection(context, configProvider),
            const SizedBox(height: 16),
            _buildConnectionSection(context, configProvider),
            const SizedBox(height: 16),
            _buildDatabaseCredentialsSection(context, configProvider),
            const SizedBox(height: 24),
            _buildActionButtons(context, configProvider, connectionProvider),
            const SizedBox(height: 16),
            _buildStatusSection(context, configProvider, connectionProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSocketConfigPage(
    BuildContext context,
    ConfigProvider configProvider,
    ConnectionProvider connectionProvider,
  ) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServerSection(context, configProvider),
            const SizedBox(height: 24),
            _buildWebSocketActionButtons(context, configProvider, connectionProvider),
            const SizedBox(height: 16),
            _buildStatusSection(context, configProvider, connectionProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSection(BuildContext context, ConfigProvider configProvider) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conexão WebSocket', style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 16),
              AppTextField(
                label: 'URL do Servidor',
                controller: _serverUrlController,
                hint: 'https://api.example.com',
                enabled: true,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'ID do Agente',
                controller: _agentIdController,
                hint: 'UUID ou Nome Único',
                enabled: true,
              ),
              const SizedBox(height: 24),
              Text('Autenticação (Opcional)', style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Usuário',
                controller: _authUsernameController,
                hint: 'Usuário para autenticação',
                enabled: true,
              ),
              const SizedBox(height: 16),
              PasswordField(
                label: 'Senha',
                controller: _authPasswordController,
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
                onPressed: () {
                  if (authProvider.isAuthenticated) {
                    authProvider.logout();
                  } else {
                    final serverUrl = _serverUrlController.text.trim();
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
                    
                    if (_authUsernameController.text.isNotEmpty &&
                        _authPasswordController.text.isNotEmpty) {
                      final credentials = AuthCredentials(
                        username: _authUsernameController.text.trim(),
                        password: _authPasswordController.text.trim(),
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
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebSocketActionButtons(
    BuildContext context,
    ConfigProvider configProvider,
    ConnectionProvider connectionProvider,
  ) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, _) {
        return Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            return Row(
              children: [
                AppButton(
                  label: connectionProvider.isConnected ? 'Desconectar' : 'Conectar',
                  isPrimary: true,
                  onPressed: () {
                    if (connectionProvider.isConnected) {
                      connectionProvider.disconnect();
                    } else {
                      final serverUrl = _serverUrlController.text.trim();
                      final agentId = _agentIdController.text.trim();
                      final authToken = authProvider.currentToken?.token;
                      
                      if (serverUrl.isNotEmpty && agentId.isNotEmpty) {
                        configProvider.updateServerUrl(serverUrl);
                        configProvider.updateAgentId(agentId);
                        connectionProvider.connect(serverUrl, agentId, authToken: authToken);
                      }
                    }
                  },
                ),
                const SizedBox(width: 16),
                AppButton(
                  label: 'Salvar Configuração',
                  isLoading: configProvider.isLoading,
                  onPressed: () {
                    _updateAllFieldsToProvider(configProvider);
                    configProvider.saveConfig();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNavigationTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: FluentTheme.of(context).cardColor, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              context,
              label: 'Configuração do Banco de Dados',
              icon: FluentIcons.database,
              isSelected: _currentPage == 0,
              onTap: () {
                setState(() {
                  _currentPage = 0;
                });
              },
            ),
          ),
          Expanded(
            child: _buildTabButton(
              context,
              label: 'Conexão WebSocket',
              icon: FluentIcons.plug_connected,
              isSelected: _currentPage == 1,
              onTap: () {
                setState(() {
                  _currentPage = 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = FluentTheme.of(context);
    final backgroundColor = isSelected ? AppColors.primary : Colors.transparent;
    final textColor = isSelected ? Colors.white : theme.resources.textFillColorPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: textColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseSectionHeader(BuildContext context) {
    return Text('Configuração do Banco de Dados', style: FluentTheme.of(context).typography.subtitle);
  }

  Widget _buildDriverSection(BuildContext context, ConfigProvider configProvider) {
    return AppDropdown<String>(
      label: 'Driver do Banco de Dados',
      value: _driverNameController.text,
      items: [
        ComboBoxItem(value: DatabaseDriver.sqlServer.displayName, child: Text(DatabaseDriver.sqlServer.displayName)),
        ComboBoxItem(value: DatabaseDriver.postgreSQL.displayName, child: Text(DatabaseDriver.postgreSQL.displayName)),
        ComboBoxItem(
          value: DatabaseDriver.sqlAnywhere.displayName,
          child: Text(DatabaseDriver.sqlAnywhere.displayName),
        ),
      ],
      onChanged: (value) {
        if (value != null && _fieldsInitialized) {
          _driverNameController.text = value;
          // Dropdown pode atualizar imediatamente pois não é digitação contínua
          configProvider.updateDriverName(value);
        }
      },
    );
  }

  Widget _buildConnectionSection(BuildContext context, ConfigProvider configProvider) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: 'Host',
            controller: _hostController,
            hint: 'localhost',
            enabled: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: NumericField(
            label: 'Porta',
            controller: _portController,
            hint: '1433',
            minValue: 1,
            maxValue: 65535,
            enabled: true,
            // onChanged removido
          ),
        ),
      ],
    );
  }

  Widget _buildDatabaseCredentialsSection(BuildContext context, ConfigProvider configProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          AppTextField(
            label: 'Nome do Banco de Dados',
            controller: _databaseNameController,
            hint: 'Nome da Base',
            enabled: true,
            // onChanged removido
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Usuário',
            controller: _usernameController,
            hint: 'Usuário',
            enabled: true,
            // onChanged removido
          ),
          const SizedBox(height: 16),
          PasswordField(
            label: 'Senha',
            controller: _passwordController,
            hint: 'Senha',
            validator: null,
            enabled: true,
            // onChanged removido
          ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ConfigProvider configProvider,
    ConnectionProvider connectionProvider,
  ) {
    return Row(
      children: [
        AppButton(
          label: 'Testar Conexão com Banco',
          isPrimary: false,
          onPressed: () {
            // Validacao simples
            if (_driverNameController.text.isNotEmpty && 
                _hostController.text.isNotEmpty && 
                _portController.text.isNotEmpty) {
              
              // Atualizar tudo antes de testar
              _updateAllFieldsToProvider(configProvider);
              
              final connectionString = configProvider.getConnectionString();
              connectionProvider.testDbConnection(connectionString);
            }
          },
        ),
        const SizedBox(width: 16),
        AppButton(
          label: 'Salvar Configuração',
          isLoading: configProvider.isLoading,
          onPressed: () {
            // Validacao simples
             if (_driverNameController.text.isNotEmpty && 
                _hostController.text.isNotEmpty && 
                _portController.text.isNotEmpty) {
                  
              // Atualiza provider com valores atuais de ambas as abas para garantir consistência
            _updateAllFieldsToProvider(configProvider);
            configProvider.saveConfig();
            }
          },
        ),
      ],
    );
  }

  void _updateAllFieldsToProvider(ConfigProvider configProvider) {
    // Database Fields
    configProvider.updateHost(_hostController.text);
    configProvider.updatePort(int.tryParse(_portController.text) ?? 1433);
    configProvider.updateDatabaseName(_databaseNameController.text);
    configProvider.updateUsername(_usernameController.text);
    configProvider.updatePassword(_passwordController.text);
    configProvider.updateDriverName(_driverNameController.text);
    
    // WebSocket Fields
    configProvider.updateServerUrl(_serverUrlController.text);
    configProvider.updateAgentId(_agentIdController.text);
    
    // WebSocket Authentication Fields
    configProvider.updateAuthUsername(_authUsernameController.text.trim().isEmpty ? null : _authUsernameController.text.trim());
    configProvider.updateAuthPassword(_authPasswordController.text.trim().isEmpty ? null : _authPasswordController.text.trim());
  }

  Widget _buildStatusSection(
    BuildContext context,
    ConfigProvider configProvider,
    ConnectionProvider connectionProvider,
  ) {
    return const ConnectionStatusWidget();
  }

}
