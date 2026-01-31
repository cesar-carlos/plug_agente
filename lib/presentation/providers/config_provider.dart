import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class ConfigProvider extends ChangeNotifier {
  ConfigProvider(
    this._saveConfigUseCase,
    this._loadConfigUseCase,
    this._configService,
    this._uuid,
  ) {
    _loadCurrentConfig();
  }
  final SaveAgentConfig _saveConfigUseCase;
  final LoadAgentConfig _loadConfigUseCase;
  final ConfigService _configService;
  final Uuid _uuid;

  Config? _currentConfig;
  bool _isLoading = false;
  String _error = '';
  bool _isPasswordVisible = false;

  Config? get currentConfig => _currentConfig;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get isPasswordVisible => _isPasswordVisible;

  Future<void> _loadCurrentConfig() async {
    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      final result = await _loadConfigUseCase(null);

      result.fold(
        (config) {
          _currentConfig = config;
          AppLogger.info('Config loaded successfully');
        },
        (exception) {
          // NotFoundFailure means no config exists, not an error
          if (exception is domain.NotFoundFailure) {
            _currentConfig = null;
            AppLogger.info('No config found, creating new one');
            _createDefaultConfig();
          } else if (exception is domain.Failure) {
            _error = exception.message;
            AppLogger.error('Failed to load config: ${exception.message}');
          } else {
            _error = exception.toString();
            AppLogger.error('Failed to load config: $exception');
          }
        },
      );
    } on Exception catch (e) {
      _error = 'Unexpected error: $e';
      AppLogger.error('Error loading config: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _createDefaultConfig() {
    _currentConfig = Config(
      id: _uuid.v4(),
      agentId: _uuid.v4(),
      driverName: DatabaseDriver.sqlServer.displayName,
      odbcDriverName: 'SQL Server Native Client 11.0',
      connectionString: '',
      username: '',
      password: '',
      databaseName: '',
      host: 'localhost',
      port: 1433,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<Result<void>> saveConfig() async {
    if (_currentConfig == null) {
      _error = 'No configuration to save';
      notifyListeners();
      return Failure(
        domain.ValidationFailure('Nenhuma configuração para salvar'),
      );
    }

    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      // Generate connection string
      final connectionString = _configService.generateConnectionString(
        _currentConfig!,
      );
      final configWithConnectionString = _currentConfig!.copyWith(
        connectionString: connectionString,
        updatedAt: DateTime.now(),
      );

      final result = await _saveConfigUseCase(configWithConnectionString);

      result.fold(
        (_) {
          _error = '';
          AppLogger.info('Config saved successfully');
        },
        (failure) {
          final failureMessage = failure is domain.Failure
              ? failure.message
              : failure.toString();
          _error = failureMessage;
          AppLogger.error('Failed to save config: $failureMessage');
        },
      );

      return result;
    } on Exception catch (e) {
      _error = 'Unexpected error: $e';
      AppLogger.error('Error saving config: $e');
      return Failure(domain.ConfigurationFailure('Erro inesperado: $e'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _ensureConfigExists() {
    if (_currentConfig == null) {
      _createDefaultConfig();
    }
  }

  void updateServerUrl(String serverUrl) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(serverUrl: serverUrl);
    notifyListeners();
  }

  void updateAgentId(String agentId) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(agentId: agentId);
    notifyListeners();
  }

  void updateDriverName(String driverName) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(driverName: driverName);
    notifyListeners();
  }

  void updateOdbcDriverName(String odbcDriverName) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(odbcDriverName: odbcDriverName);
    notifyListeners();
  }

  void updateUsername(String username) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(username: username);
    notifyListeners();
  }

  void updatePassword(String password) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(password: password);
    notifyListeners();
  }

  void updateAuthUsername(String? authUsername) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(authUsername: authUsername);
    notifyListeners();
  }

  void updateAuthPassword(String? authPassword) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(authPassword: authPassword);
    notifyListeners();
  }

  void updateDatabaseName(String databaseName) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(databaseName: databaseName);
    notifyListeners();
  }

  void updateHost(String host) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(host: host);
    notifyListeners();
  }

  void updatePort(int port) {
    _ensureConfigExists();
    _currentConfig = _currentConfig!.copyWith(port: port);
    notifyListeners();
  }

  void togglePasswordVisibility() {
    _isPasswordVisible = !_isPasswordVisible;
    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  String getConnectionString() {
    if (_currentConfig == null) return '';
    return _configService.generateConnectionString(_currentConfig!);
  }
}
