import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:result_dart/result_dart.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class ConnectionProvider extends ChangeNotifier {
  ConnectionProvider(
    this._connectToHubUseCase,
    this._testDbConnectionUseCase,
    this._checkOdbcDriverUseCase, {
    AuthProvider? authProvider,
    ConfigProvider? configProvider,
  }) : _authProvider = authProvider,
       _configProvider = configProvider;
  final ConnectToHub _connectToHubUseCase;
  final TestDbConnection _testDbConnectionUseCase;
  final CheckOdbcDriver _checkOdbcDriverUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  void setConfigProvider(ConfigProvider configProvider) {
    _configProvider = configProvider;
  }

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _error = '';
  bool _isDbConnected = false;
  bool _isReconnecting = false;
  bool _isCheckingDriver = false;

  ConnectionStatus get status => _status;
  String get error => _error;
  bool get isDbConnected => _isDbConnected;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isReconnecting => _isReconnecting;
  bool get isCheckingDriver => _isCheckingDriver;

  Future<void> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    _status = ConnectionStatus.connecting;
    _error = '';
    notifyListeners();

    final transportClient = getIt<ITransportClient>();
    transportClient.setOnTokenExpired(_handleTokenExpired);
    transportClient.setOnReconnectionNeeded(_handleReconnectionNeeded);

    final result = await _connectToHubUseCase(
      serverUrl,
      agentId,
      authToken: authToken,
    );

    result.fold(
      (_) {
        _status = ConnectionStatus.connected;
        AppLogger.info('Connected to hub successfully');
      },
      (failure) {
        _status = ConnectionStatus.error;
        _error = failure.toUserMessage();
        AppLogger.error('Failed to connect to hub: $_error');
      },
    );

    notifyListeners();
  }

  Future<void> disconnect() async {
    _status = ConnectionStatus.disconnected;
    _error = '';
    notifyListeners();

    AppLogger.info('Disconnected from hub');
  }

  Future<Result<bool>> testDbConnection(String connectionString) async {
    final result = await _testDbConnectionUseCase(connectionString);

    result.fold(
      (isConnected) {
        _isDbConnected = isConnected;
        if (isConnected) {
          AppLogger.info('Database connection test successful');
        } else {
          AppLogger.warning('Database connection test failed');
        }
      },
      (failure) {
        _isDbConnected = false;
        AppLogger.error(
          'Database connection test failed: ${failure.toUserMessage()}',
        );
      },
    );

    notifyListeners();
    return result;
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  Future<Result<bool>> checkOdbcDriver(String driverName) async {
    _isCheckingDriver = true;
    _error = '';
    notifyListeners();

    final result = await _checkOdbcDriverUseCase(driverName);

    result.fold(
      (isInstalled) {
        if (isInstalled) {
          AppLogger.info('ODBC driver "$driverName" is installed');
        } else {
          AppLogger.warning('ODBC driver "$driverName" is not installed');
        }
      },
      (failure) {
        _error = failure.toUserMessage();
        AppLogger.error('Failed to check ODBC driver: $_error');
      },
    );

    _isCheckingDriver = false;
    notifyListeners();
    return result;
  }

  Future<void> _handleTokenExpired() async {
    if (_isReconnecting) return;

    _isReconnecting = true;
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Token expired, attempting refresh...');
    notifyListeners();

    try {
      final transportClient = getIt<ITransportClient>();
      await transportClient.disconnect();

      final serverUrl = _configProvider?.currentConfig?.serverUrl;
      if (serverUrl != null && serverUrl.isNotEmpty && _authProvider != null) {
        await _authProvider!.refreshToken(serverUrl);

        final newToken = _authProvider!.currentToken;
        final agentId = _configProvider?.currentConfig?.agentId ?? '';

        if (newToken != null && agentId.isNotEmpty) {
          await connect(serverUrl, agentId, authToken: newToken.token);
          AppLogger.info('Reconnected with refreshed token successfully');
        } else {
          _status = ConnectionStatus.error;
          _error = 'Failed to get new token or agent ID';
          AppLogger.error('Failed to get new token or agent ID after refresh');
        }
      } else {
        _status = ConnectionStatus.error;
        _error = 'Server URL, AuthProvider or ConfigProvider not available';
        AppLogger.error(
          'Server URL, AuthProvider or ConfigProvider not available for token refresh',
        );
      }
    } on Exception catch (e) {
      _status = ConnectionStatus.error;
      _error = 'Failed to refresh token: $e';
      AppLogger.error('Token refresh failed: $e');
    }

    _isReconnecting = false;
    notifyListeners();
  }

  Future<void> _handleReconnectionNeeded() async {
    if (_isReconnecting) return;

    _isReconnecting = true;
    _status = ConnectionStatus.reconnecting;
    AppLogger.warning('Reconnection needed after failed attempts');
    notifyListeners();

    await Future<void>.delayed(const Duration(seconds: 2));

    try {
      final serverUrl = _configProvider?.currentConfig?.serverUrl;
      final agentId = _configProvider?.currentConfig?.agentId;
      final authToken =
          _authProvider?.currentToken?.token ??
          _configProvider?.currentConfig?.authToken;

      if (serverUrl != null &&
          serverUrl.isNotEmpty &&
          agentId != null &&
          agentId.isNotEmpty) {
        await connect(serverUrl, agentId, authToken: authToken);
        AppLogger.info('Attempted manual reconnection');
      } else {
        _status = ConnectionStatus.error;
        _error = 'Server URL or Agent ID not available for reconnection';
        AppLogger.error(
          'Server URL or Agent ID not available for reconnection',
        );
      }
    } on Exception catch (e) {
      _status = ConnectionStatus.error;
      _error = 'Failed to reconnect: $e';
      AppLogger.error('Manual reconnection failed: $e');
    }

    _isReconnecting = false;
    notifyListeners();
  }
}
