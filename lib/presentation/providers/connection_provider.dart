import 'package:flutter/foundation.dart';

import '../../application/use_cases/connect_to_hub.dart';
import '../../application/use_cases/test_db_connection.dart';
import '../../core/logger/app_logger.dart';
import '../../core/di/service_locator.dart';
import '../../domain/repositories/i_transport_client.dart';
import '../../domain/errors/failures.dart' as domain;
import 'auth_provider.dart';
import 'config_provider.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting, error }

class ConnectionProvider extends ChangeNotifier {
  final ConnectToHub _connectToHubUseCase;
  final TestDbConnection _testDbConnectionUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;

  ConnectionProvider(
    this._connectToHubUseCase,
    this._testDbConnectionUseCase, {
    AuthProvider? authProvider,
    ConfigProvider? configProvider,
  }) : _authProvider = authProvider,
       _configProvider = configProvider;

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

  ConnectionStatus get status => _status;
  String get error => _error;
  bool get isDbConnected => _isDbConnected;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isReconnecting => _isReconnecting;

  Future<void> connect(String serverUrl, String agentId, {String? authToken}) async {
    _status = ConnectionStatus.connecting;
    _error = '';
    notifyListeners();

    try {
      final transportClient = getIt<ITransportClient>();
      transportClient.setOnTokenExpired(_handleTokenExpired);
      transportClient.setOnReconnectionNeeded(_handleReconnectionNeeded);

      final result = await _connectToHubUseCase(serverUrl, agentId, authToken: authToken);

      result.fold(
        (_) {
          _status = ConnectionStatus.connected;
          AppLogger.info('Connected to hub successfully');
        },
        (failure) {
          _status = ConnectionStatus.error;
          final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
          _error = failureMessage;
          AppLogger.error('Failed to connect to hub: $failureMessage');
        },
      );
    } catch (e) {
      _status = ConnectionStatus.error;
      _error = 'Unexpected error: $e';
      AppLogger.error('Unexpected error during connection: $e');
    }

    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      _status = ConnectionStatus.disconnected;
      _error = '';
      notifyListeners();

      // Call disconnect on transport client
      AppLogger.info('Disconnected from hub');
    } catch (e) {
      _error = 'Failed to disconnect: $e';
      AppLogger.error('Error during disconnection: $e');
      notifyListeners();
    }
  }

  Future<void> testDbConnection(String connectionString) async {
    try {
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
          final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
          AppLogger.error('Database connection test failed: $failureMessage');
        },
      );

      notifyListeners();
    } catch (e) {
      _isDbConnected = false;
      AppLogger.error('Error testing database connection: $e');
      notifyListeners();
    }
  }

  void clearError() {
    _error = '';
    notifyListeners();
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
        AppLogger.error('Server URL, AuthProvider or ConfigProvider not available for token refresh');
      }
    } catch (e) {
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

    await Future.delayed(const Duration(seconds: 2));

    try {
      final serverUrl = _configProvider?.currentConfig?.serverUrl;
      final agentId = _configProvider?.currentConfig?.agentId;
      final authToken = _authProvider?.currentToken?.token ?? _configProvider?.currentConfig?.authToken;

      if (serverUrl != null && serverUrl.isNotEmpty && agentId != null && agentId.isNotEmpty) {
        await connect(serverUrl, agentId, authToken: authToken);
        AppLogger.info('Attempted manual reconnection');
      } else {
        _status = ConnectionStatus.error;
        _error = 'Server URL or Agent ID not available for reconnection';
        AppLogger.error('Server URL or Agent ID not available for reconnection');
      }
    } catch (e) {
      _status = ConnectionStatus.error;
      _error = 'Failed to reconnect: $e';
      AppLogger.error('Manual reconnection failed: $e');
    }

    _isReconnecting = false;
    notifyListeners();
  }
}
