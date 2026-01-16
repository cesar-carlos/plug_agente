import 'package:flutter/foundation.dart';
import '../../domain/entities/config.dart';
import '../../domain/value_objects/database_driver.dart';
import '../../domain/errors/failures.dart';
import '../../application/use_cases/save_agent_config.dart';
import '../../application/use_cases/load_agent_config.dart';
import '../../application/services/config_service.dart';
import '../../core/logger/app_logger.dart';
import 'package:uuid/uuid.dart';

class ConfigProvider extends ChangeNotifier {
  final SaveAgentConfig _saveConfigUseCase;
  final LoadAgentConfig _loadConfigUseCase;
  final ConfigService _configService;
  final Uuid _uuid;

  ConfigProvider(
    this._saveConfigUseCase,
    this._loadConfigUseCase,
    this._configService,
    this._uuid,
  ) {
    _loadCurrentConfig();
  }

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
          if (exception is NotFoundFailure) {
            _currentConfig = null;
            AppLogger.info('No config found, creating new one');
            _createDefaultConfig();
          } else if (exception is Failure) {
            _error = exception.message;
            AppLogger.error('Failed to load config: ${exception.message}');
          } else {
            _error = exception.toString();
            AppLogger.error('Failed to load config: $exception');
          }
        },
      );
    } catch (e) {
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
      serverUrl: 'https://api.example.com',
      agentId: _uuid.v4(),
      driverName: DatabaseDriver.sqlServer.displayName,
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

  Future<void> saveConfig() async {
    if (_currentConfig == null) {
      _error = 'No configuration to save';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      // Generate connection string
      final connectionString = _configService.generateConnectionString(_currentConfig!);
      final configWithConnectionString = _currentConfig!.copyWith(
        connectionString: connectionString,
        updatedAt: DateTime.now(),
      );

      final result = await _saveConfigUseCase(configWithConnectionString);
      
      result.fold(
        (_) {
          AppLogger.info('Config saved successfully');
        },
        (exception) {
          if (exception is Failure) {
            _error = exception.message;
            AppLogger.error('Failed to save config: ${exception.message}');
          } else {
            _error = exception.toString();
            AppLogger.error('Failed to save config: $exception');
          }
        },
      );
    } catch (e) {
      _error = 'Unexpected error: $e';
      AppLogger.error('Error saving config: $e');
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