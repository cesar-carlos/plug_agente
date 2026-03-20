import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/reconnect_delay_calculator.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
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
    ITransportClient? transportClient,
    Duration initialReconnectDelay = _defaultInitialReconnectDelay,
    Duration maxReconnectDelay = _defaultMaxReconnectDelay,
    int tokenRefreshIntervalAttempts = _defaultTokenRefreshIntervalAttempts,
    int maxReconnectAttempts = _defaultMaxReconnectAttempts,
    Random? random,
  }) : _authProvider = authProvider,
       _configProvider = configProvider,
       _transportClientOverride = transportClient,
       _initialReconnectDelay = initialReconnectDelay,
       _maxReconnectDelay = maxReconnectDelay,
       _tokenRefreshIntervalAttempts = tokenRefreshIntervalAttempts,
       _maxReconnectAttempts = maxReconnectAttempts,
       _random = random {
    if (_tokenRefreshIntervalAttempts < 1) {
      throw ArgumentError.value(
        tokenRefreshIntervalAttempts,
        'tokenRefreshIntervalAttempts',
        'must be >= 1',
      );
    }
    if (_maxReconnectAttempts < 1) {
      throw ArgumentError.value(
        maxReconnectAttempts,
        'maxReconnectAttempts',
        'must be >= 1',
      );
    }
  }
  final ConnectToHub _connectToHubUseCase;
  final TestDbConnection _testDbConnectionUseCase;
  final CheckOdbcDriver _checkOdbcDriverUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  final ITransportClient? _transportClientOverride;

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
  bool _isDisconnectRequested = false;
  String? _lastServerUrl;
  String? _lastAgentId;
  String? _lastAuthToken;

  static const Duration _defaultInitialReconnectDelay = Duration(
    seconds: AppConstants.reconnectIntervalSeconds,
  );
  static const Duration _defaultMaxReconnectDelay = Duration(seconds: 60);
  static const int _defaultTokenRefreshIntervalAttempts = 4;
  static const int _defaultMaxReconnectAttempts =
      AppConstants.maxReconnectAttempts;
  final Duration _initialReconnectDelay;
  final Duration _maxReconnectDelay;
  final int _tokenRefreshIntervalAttempts;
  final int _maxReconnectAttempts;
  final Random? _random;

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
    _isDisconnectRequested = false;
    _lastServerUrl = serverUrl;
    _lastAgentId = agentId;
    if (authToken != null && authToken.trim().isNotEmpty) {
      _lastAuthToken = authToken.trim();
    }

    _status = ConnectionStatus.connecting;
    _error = '';
    notifyListeners();

    final transportClient =
        _transportClientOverride ?? getIt<ITransportClient>();
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
        _error = '';
        AppLogger.info('Connected to hub successfully');
      },
      (failure) {
        _status = ConnectionStatus.error;
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Failed to connect to hub: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    notifyListeners();
  }

  Future<void> disconnect() async {
    _isDisconnectRequested = true;
    final transportClient =
        _transportClientOverride ?? getIt<ITransportClient>();
    await transportClient.disconnect();
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
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Database connection test failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
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
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Failed to check ODBC driver: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    _isCheckingDriver = false;
    notifyListeners();
    return result;
  }

  Future<void> _handleTokenExpired() async {
    if (_isReconnecting || _isDisconnectRequested) {
      return;
    }

    _isReconnecting = true;
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Token expired, attempting refresh...');
    notifyListeners();

    try {
      final transportClient =
          _transportClientOverride ?? getIt<ITransportClient>();
      await transportClient.disconnect();

      final context = _resolveConnectionContext();
      if (context == null) {
        _status = ConnectionStatus.error;
        _error = 'Connection context unavailable for token refresh';
        AppLogger.error('Cannot refresh token without connection context');
      } else {
        final refreshedToken = await _tryRefreshToken(context.serverUrl);
        if (refreshedToken == null) {
          _status = ConnectionStatus.error;
          _error = 'Failed to refresh authentication token';
          AppLogger.error('Token refresh failed during reconnect policy');
        } else {
          final connected = await _attemptReconnect(
            context.serverUrl,
            context.agentId,
            authToken: refreshedToken,
          );
          if (connected) {
            AppLogger.info('Reconnected with refreshed token successfully');
          }
        }
      }
    } on Exception catch (error, stackTrace) {
      _status = ConnectionStatus.error;
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to refresh token',
        cause: error,
        context: {'operation': 'handleTokenExpired'},
      );
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Token refresh failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    }

    _isReconnecting = false;
    notifyListeners();
  }

  Future<void> _handleReconnectionNeeded() async {
    if (_isReconnecting || _isDisconnectRequested) {
      return;
    }

    _isReconnecting = true;
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Reconnection needed after failed attempts');
    notifyListeners();

    try {
      final context = _resolveConnectionContext();
      if (context == null) {
        _status = ConnectionStatus.error;
        _error = 'Server URL or Agent ID not available for reconnection';
        AppLogger.error('Missing server URL or agent ID for reconnection');
      } else {
        final connected = await _recoverConnection(context);
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          _error = '';
          AppLogger.info('Reconnection loop cancelled by user disconnect');
          return;
        }
        if (!connected) {
          _status = ConnectionStatus.error;
          _error = 'Failed to recover connection after retries';
          AppLogger.error('Connection recovery failed after retries');
        }
      }
    } on Exception catch (error, stackTrace) {
      _status = ConnectionStatus.error;
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to reconnect to the hub',
        cause: error,
        context: {'operation': 'handleReconnectionNeeded'},
      );
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Manual reconnection failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    }

    _isReconnecting = false;
    notifyListeners();
  }

  Future<bool> _recoverConnection(_ConnectionContext context) async {
    var authToken = _resolveAuthTokenForReconnect();
    for (
      var attempt = 1;
      attempt <= _maxReconnectAttempts && !_isDisconnectRequested;
      attempt++
    ) {
      final delay = _computeReconnectDelay(attempt);
      if (delay > Duration.zero) {
        AppLogger.info(
          'resilience: reconnect_delay_ms attempt=$attempt '
          'delay_ms=${delay.inMilliseconds} agent_id=${context.agentId}',
        );
        await Future<void>.delayed(delay);
      }

      AppLogger.info(
        'resilience: connect_attempt attempt=$attempt agent_id=${context.agentId}',
      );
      final connected = await _attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: authToken,
      );
      if (connected) {
        AppLogger.info('Connection recovered on attempt $attempt');
        return true;
      }

      if (attempt % _tokenRefreshIntervalAttempts == 0) {
        final refreshedToken = await _tryRefreshToken(context.serverUrl);
        if (refreshedToken != null) {
          authToken = refreshedToken;
        }
      }
    }

    AppLogger.warning(
      'Connection recovery exhausted maximum attempts ($_maxReconnectAttempts)',
    );
    return false;
  }

  Future<bool> _attemptReconnect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    final result = await _connectToHubUseCase(
      serverUrl,
      agentId,
      authToken: authToken,
    );

    return result.fold(
      (_) {
        _status = ConnectionStatus.connected;
        _error = '';
        _lastServerUrl = serverUrl;
        _lastAgentId = agentId;
        if (authToken != null && authToken.trim().isNotEmpty) {
          _lastAuthToken = authToken.trim();
        }
        AppLogger.info('Reconnection attempt succeeded');
        return true;
      },
      (failure) {
        _status = ConnectionStatus.reconnecting;
        _error = failure.toDisplayMessage();
        AppLogger.warning(
          'Reconnection attempt failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        return false;
      },
    );
  }

  Future<String?> _tryRefreshToken(String serverUrl) async {
    final authProvider = _authProvider;
    if (authProvider == null) {
      return null;
    }

    await authProvider.refreshToken(serverUrl);
    final refreshedToken = authProvider.currentToken?.token;
    if (refreshedToken == null || refreshedToken.trim().isEmpty) {
      return null;
    }

    return _lastAuthToken = refreshedToken.trim();
  }

  _ConnectionContext? _resolveConnectionContext() {
    final config = _configProvider?.currentConfig;
    final configServerUrl = config?.serverUrl.trim();
    final configAgentId = config?.agentId.trim();
    final serverUrl =
        _lastServerUrl ??
        ((configServerUrl != null && configServerUrl.isNotEmpty)
            ? configServerUrl
            : null);
    final agentId =
        _lastAgentId ??
        ((configAgentId != null && configAgentId.isNotEmpty)
            ? configAgentId
            : null);

    if (serverUrl == null || agentId == null) {
      return null;
    }

    return _ConnectionContext(serverUrl: serverUrl, agentId: agentId);
  }

  String? _resolveAuthTokenForReconnect() {
    final liveToken = _authProvider?.currentToken?.token;
    if (liveToken != null && liveToken.trim().isNotEmpty) {
      return _lastAuthToken = liveToken.trim();
    }

    final configToken = _configProvider?.currentConfig?.authToken;
    if (configToken != null && configToken.trim().isNotEmpty) {
      return _lastAuthToken = configToken.trim();
    }

    return _lastAuthToken;
  }

  Duration _computeReconnectDelay(int attempt) {
    return computeReconnectDelay(
      attempt: attempt,
      initialDelay: _initialReconnectDelay,
      maxDelay: _maxReconnectDelay,
      random: _random,
    );
  }
}

class _ConnectionContext {
  const _ConnectionContext({
    required this.serverUrl,
    required this.agentId,
  });

  final String serverUrl;
  final String agentId;
}
