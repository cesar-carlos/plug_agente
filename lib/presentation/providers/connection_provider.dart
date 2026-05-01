import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/services/hub_recovery_auth_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/reconnect_delay_calculator.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
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
    HubRecoveryAuthCoordinator? hubRecoveryAuthCoordinator,
    CheckHubAvailability? checkHubAvailabilityUseCase,
    AuthProvider? authProvider,
    ConfigProvider? configProvider,
    ITransportClient? transportClient,
    HubResilienceConfig? hubResilience,
    FeatureFlags? featureFlags,
    Duration initialReconnectDelay = _defaultInitialReconnectDelay,
    Duration maxReconnectDelay = _defaultMaxReconnectDelay,
    int tokenRefreshIntervalAttempts = _defaultTokenRefreshIntervalAttempts,
    int maxReconnectAttempts = _defaultMaxReconnectAttempts,
    int hardReloginFailureThreshold = _defaultHardReloginFailureThreshold,
    bool enableHardReloginRecovery = _defaultEnableHardReloginRecovery,
    Duration? hubPersistentRetryInterval,
    int? hubPersistentRetryMaxFailedTicks,
    Random? random,
  }) : _checkHubAvailabilityUseCase = checkHubAvailabilityUseCase,
       _hubRecoveryAuthCoordinator = hubRecoveryAuthCoordinator,
       _authProvider = authProvider,
       _configProvider = configProvider,
       _transportClientOverride = transportClient,
       _hubResilience = hubResilience,
       _featureFlags = featureFlags,
       _initialReconnectDelay = initialReconnectDelay,
       _maxReconnectDelay = maxReconnectDelay,
       _tokenRefreshIntervalAttempts = tokenRefreshIntervalAttempts,
       _maxReconnectAttempts = maxReconnectAttempts,
       _hardReloginFailureThresholdOverride = hardReloginFailureThreshold,
       _enableHardReloginRecoveryOverride = enableHardReloginRecovery,
       _hubPersistentRetryIntervalOverride = hubPersistentRetryInterval,
       _hubPersistentRetryMaxFailedTicksOverride = hubPersistentRetryMaxFailedTicks,
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
    if (_hardReloginFailureThresholdOverride < 1) {
      throw ArgumentError.value(
        hardReloginFailureThreshold,
        'hardReloginFailureThreshold',
        'must be >= 1',
      );
    }
  }
  final CheckHubAvailability? _checkHubAvailabilityUseCase;
  final HubRecoveryAuthCoordinator? _hubRecoveryAuthCoordinator;
  final ConnectToHub _connectToHubUseCase;
  final TestDbConnection _testDbConnectionUseCase;
  final CheckOdbcDriver _checkOdbcDriverUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  final ITransportClient? _transportClientOverride;
  final HubResilienceConfig? _hubResilience;
  final FeatureFlags? _featureFlags;

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
  bool _sessionAuthInvalid = false;
  int _consecutiveReconnectFailures = 0;
  bool _hardReloginAttemptedInCycle = false;
  Timer? _hubPersistentRetryTimer;
  int _persistentRetryTickCount = 0;
  int _persistentFailureCount = 0;
  bool _persistentRetryInFlight = false;

  static const Duration _defaultInitialReconnectDelay = Duration(
    seconds: AppConstants.reconnectIntervalSeconds,
  );
  static const Duration _defaultMaxReconnectDelay = Duration(seconds: 60);

  /// Burst-mode token refresh cadence: trigger a refresh after every Nth
  /// failed reconnect attempt. MUST be `<= _defaultMaxReconnectAttempts` so the
  /// refresh actually fires inside the burst window (otherwise the periodic
  /// check `attempt % N == 0` becomes dead code).
  static const int _defaultTokenRefreshIntervalAttempts = 2;
  static const int _defaultMaxReconnectAttempts = ConnectionConstants.defaultHubRecoveryBurstMaxAttempts;
  final Duration _initialReconnectDelay;
  final Duration _maxReconnectDelay;
  final int _tokenRefreshIntervalAttempts;
  final int _maxReconnectAttempts;
  final int _hardReloginFailureThresholdOverride;
  final bool _enableHardReloginRecoveryOverride;
  final Duration? _hubPersistentRetryIntervalOverride;
  final int? _hubPersistentRetryMaxFailedTicksOverride;
  final Random? _random;

  static const int _defaultHardReloginFailureThreshold = 3;
  static const bool _defaultEnableHardReloginRecovery = true;
  static const int _hardReloginMinThreshold = 1;
  static const int _hardReloginMaxThreshold = 20;

  Duration get _effectiveHubPersistentRetryInterval =>
      _hubPersistentRetryIntervalOverride ??
      _hubResilience?.persistentRetryInterval ??
      ConnectionConstants.hubPersistentRetryInterval;

  int get _effectiveHubPersistentRetryMaxFailedTicks =>
      _hubPersistentRetryMaxFailedTicksOverride ??
      _hubResilience?.maxFailedTicks ??
      ConnectionConstants.hubPersistentRetryMaxFailedTicks;

  bool get _effectiveHardReloginRecoveryEnabled =>
      _featureFlags?.enableHubHardReloginRecovery ?? _enableHardReloginRecoveryOverride;

  int get _effectiveHardReloginFailureThreshold {
    final configured = _featureFlags?.hubHardReloginFailureThreshold ?? _hardReloginFailureThresholdOverride;
    return configured.clamp(_hardReloginMinThreshold, _hardReloginMaxThreshold);
  }

  ConnectionStatus get status => _status;
  String get error => _error;
  bool get isDbConnected => _isDbConnected;

  /// Updates the DB status chip shown next to hub status when connectivity is
  /// proven elsewhere (e.g. successful Playground query or test from Playground).
  void setDbConnectionIndicator(bool connected) {
    if (_isDbConnected == connected) {
      return;
    }
    _isDbConnected = connected;
    notifyListeners();
  }

  bool get isConnected => _status == ConnectionStatus.connected;

  /// True while an internal recovery handler runs, or when the hub link is in a
  /// reconnecting state (including Socket.IO lifecycle).
  bool get isReconnecting => _isReconnecting || _status == ConnectionStatus.reconnecting;
  bool get isCheckingDriver => _isCheckingDriver;

  Future<void> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    _cancelPersistentRetryTimer();
    _persistentFailureCount = 0;
    _consecutiveReconnectFailures = 0;
    _hardReloginAttemptedInCycle = false;
    _sessionAuthInvalid = false;
    _isDisconnectRequested = false;
    _lastServerUrl = serverUrl;
    _lastAgentId = agentId;
    if (authToken != null && authToken.trim().isNotEmpty) {
      _lastAuthToken = authToken.trim();
    }

    _status = ConnectionStatus.connecting;
    _error = '';
    notifyListeners();

    final transportClient = _transportClientOverride ?? getIt<ITransportClient>();
    transportClient.setOnTokenExpired(_handleTokenExpired);
    transportClient.setOnReconnectionNeeded(_handleReconnectionNeeded);
    transportClient.setOnHubLifecycle(_handleHubLifecycle);

    final result = await _connectToHubUseCase(
      serverUrl,
      agentId,
      authToken: authToken,
    );

    result.fold(
      (_) {
        if (_isDisconnectRequested) return;
        _cancelPersistentRetryTimer();
        _status = ConnectionStatus.connected;
        _error = '';
        AppLogger.info('Connected to hub successfully');
      },
      (failure) {
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          return;
        }
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
    _cancelPersistentRetryTimer();
    _hardReloginAttemptedInCycle = false;
    _consecutiveReconnectFailures = 0;
    final transportClient = _transportClientOverride ?? getIt<ITransportClient>();
    await transportClient.disconnect();
    _status = ConnectionStatus.disconnected;
    _error = '';
    notifyListeners();

    AppLogger.info('Disconnected from hub');
  }

  Future<Result<bool>> testDbConnection(
    String connectionString, {
    bool recordGlobalError = true,
  }) async {
    final result = await _testDbConnectionUseCase(connectionString);

    result.fold(
      (bool isConnected) {
        setDbConnectionIndicator(isConnected);
        if (isConnected) {
          AppLogger.info('Database connection test successful');
        } else {
          AppLogger.warning('Database connection test failed');
        }
      },
      (Object failure) {
        setDbConnectionIndicator(false);
        if (recordGlobalError) {
          _error = failure.toDisplayMessage();
        }
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
    if (_isDisconnectRequested) {
      return;
    }

    // During hub recovery burst/persistent retry, `_isReconnecting` is true but we still
    // need to refresh — otherwise `_handleConnectionError` fires `_onTokenExpired` and we
    // never rotate JWT until user logs out/in manually.
    if (_isReconnecting) {
      final context = _resolveConnectionContext();
      if (context != null) {
        AppLogger.warning(
          'Hub reported authentication failure during reconnect; refreshing token',
        );
        await _tryRefreshToken(context.serverUrl);
      }
      return;
    }

    _isReconnecting = true;
    _hardReloginAttemptedInCycle = false;
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Token expired, attempting refresh...');
    notifyListeners();

    try {
      final transportClient = _transportClientOverride ?? getIt<ITransportClient>();
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
          } else if (!_isDisconnectRequested) {
            AppLogger.warning(
              'Single reconnect with refreshed token failed; escalating to recovery burst',
            );
            final recovered = await _recoverConnection(context);
            if (!recovered && !_isDisconnectRequested) {
              AppLogger.warning(
                'Recovery burst exhausted after token refresh; starting persistent retry',
              );
              _startPersistentRetry();
            }
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
    _hardReloginAttemptedInCycle = false;
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
          if (_isDisconnectRequested) {
            return;
          }
          _status = ConnectionStatus.reconnecting;
          _error = '';
          AppLogger.warning('Connection burst recovery exhausted; starting persistent hub retry');
          _startPersistentRetry();
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
    await _tryRefreshToken(context.serverUrl);
    var authToken = _resolveAuthTokenForReconnect();
    for (var attempt = 1; attempt <= _maxReconnectAttempts && !_isDisconnectRequested; attempt++) {
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
      final hubReachable = await _isHubReachableForReconnect(
        context.serverUrl,
        stage: 'burst',
      );
      if (!hubReachable) {
        AppLogger.info(
          'resilience: hub_unreachable_skip_connect attempt=$attempt agent_id=${context.agentId}',
        );
        continue;
      }
      final connected = await _attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: authToken,
      );
      if (connected) {
        AppLogger.info('Connection recovered on attempt $attempt');
        return true;
      }

      if (_shouldEscalateToHardRelogin) {
        final hardReloginToken = await _attemptHardRelogin(context);
        if (hardReloginToken == null) {
          if (_status == ConnectionStatus.error) {
            return false;
          }
        } else {
          authToken = hardReloginToken;
          final hubReachableAfterRelogin = await _isHubReachableForReconnect(
            context.serverUrl,
            stage: 'hard_relogin',
          );
          if (hubReachableAfterRelogin) {
            final connectedAfterRelogin = await _attemptReconnect(
              context.serverUrl,
              context.agentId,
              authToken: authToken,
            );
            if (connectedAfterRelogin) {
              AppLogger.info('Connection recovered after hard relogin');
              return true;
            }
          }
        }
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
    bool recordErrorMessage = true,
  }) async {
    final result = await _connectToHubUseCase(
      serverUrl,
      agentId,
      authToken: authToken,
    );

    return result.fold(
      (_) {
        _cancelPersistentRetryTimer();
        _persistentFailureCount = 0;
        _consecutiveReconnectFailures = 0;
        _sessionAuthInvalid = false;
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
        _consecutiveReconnectFailures++;
        _status = ConnectionStatus.reconnecting;
        _error = recordErrorMessage ? failure.toDisplayMessage() : '';
        AppLogger.warning(
          'Reconnection attempt failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        return false;
      },
    );
  }

  void _handleHubLifecycle(HubLifecycleNotification notification) {
    if (_isDisconnectRequested) {
      return;
    }
    switch (notification) {
      case HubTransportDisconnected():
        if (_status == ConnectionStatus.disconnected) {
          return;
        }
        _status = ConnectionStatus.reconnecting;
        _error = '';
        notifyListeners();
      case HubTransportReconnectAttempt(:final attemptNumber):
        AppLogger.info(
          'resilience: hub_socket_reconnect_attempt attempt=$attemptNumber '
          'status=${_status.name}',
        );
        if (_status == ConnectionStatus.connected) {
          _status = ConnectionStatus.reconnecting;
          _error = '';
          notifyListeners();
        }
      case HubTransportAutoReconnectSucceeded():
        _cancelPersistentRetryTimer();
        _status = ConnectionStatus.connected;
        _error = '';
        notifyListeners();
    }
  }

  void _cancelPersistentRetryTimer() {
    _hubPersistentRetryTimer?.cancel();
    _hubPersistentRetryTimer = null;
  }

  void _startPersistentRetry() {
    _cancelPersistentRetryTimer();
    _persistentRetryTickCount = 0;
    _persistentFailureCount = 0;
    unawaited(_persistentRetryTick());
    _hubPersistentRetryTimer = Timer.periodic(_effectiveHubPersistentRetryInterval, (_) {
      unawaited(_persistentRetryTick());
    });
  }

  Future<void> _persistentRetryTick() async {
    if (_persistentRetryInFlight) {
      return;
    }
    _persistentRetryInFlight = true;
    try {
      if (_isDisconnectRequested) {
        _cancelPersistentRetryTimer();
        return;
      }
      final context = _resolveConnectionContext();
      if (context == null) {
        AppLogger.warning('persistent hub retry skipped: missing server URL or agent ID');
        _cancelPersistentRetryTimer();
        return;
      }
      _persistentRetryTickCount++;
      AppLogger.info(
        'resilience: hub_persistent_retry_tick tick=$_persistentRetryTickCount '
        'agent_id=${context.agentId}',
      );
      if (_persistentRetryTickCount % _tokenRefreshIntervalAttempts == 0) {
        await _tryRefreshToken(context.serverUrl);
      }
      final hubReachable = await _isHubReachableForReconnect(
        context.serverUrl,
        stage: 'persistent',
      );
      if (!hubReachable) {
        AppLogger.info(
          'resilience: hub_unreachable_skip_connect tick=$_persistentRetryTickCount agent_id=${context.agentId}',
        );
        return;
      }
      final authToken = _resolveAuthTokenForReconnect();
      final ok = await _attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: authToken,
        recordErrorMessage: false,
      );
      if (ok || _isDisconnectRequested) {
        return;
      }
      if (_shouldEscalateToHardRelogin) {
        final hardReloginToken = await _attemptHardRelogin(context);
        if (hardReloginToken == null) {
          if (_status == ConnectionStatus.error) {
            return;
          }
        } else {
          final connectedAfterRelogin = await _attemptReconnect(
            context.serverUrl,
            context.agentId,
            authToken: hardReloginToken,
            recordErrorMessage: false,
          );
          if (connectedAfterRelogin) {
            return;
          }
        }
      }
      if (_effectiveHubPersistentRetryMaxFailedTicks > 0) {
        _persistentFailureCount++;
        AppLogger.info(
          'resilience: hub_persistent_retry_failure '
          'count=$_persistentFailureCount '
          'max=$_effectiveHubPersistentRetryMaxFailedTicks '
          'agent_id=${context.agentId}',
        );
        if (_persistentFailureCount >= _effectiveHubPersistentRetryMaxFailedTicks) {
          _cancelPersistentRetryTimer();
          _status = ConnectionStatus.error;
          _error = ConnectionConstants.hubPersistentRetryExhaustedMessage;
          notifyListeners();
        }
      }
    } finally {
      _persistentRetryInFlight = false;
    }
  }

  @override
  void dispose() {
    _cancelPersistentRetryTimer();
    super.dispose();
  }

  Future<String?> _tryRefreshToken(String serverUrl) async {
    final coordinator = _hubRecoveryAuthCoordinator;
    final authProvider = _authProvider;
    if (coordinator == null || authProvider == null) {
      _sessionAuthInvalid = true;
      return null;
    }

    final refreshResult = await coordinator.refreshSession(
      serverUrl,
      currentToken: authProvider.currentToken,
    );
    return refreshResult.fold(
      (token) {
        authProvider.restoreToken(token);
        _sessionAuthInvalid = false;
        return _lastAuthToken = token.token.trim();
      },
      (failure) {
        authProvider.setRecoveryError(failure.toDisplayMessage());
        _sessionAuthInvalid = true;
        return null;
      },
    );
  }

  _ConnectionContext? _resolveConnectionContext() {
    final config = _configProvider?.currentConfig;
    final configServerUrl = config?.serverUrl.trim();
    final configAgentId = config?.agentId.trim();
    final serverUrl =
        _lastServerUrl ?? ((configServerUrl != null && configServerUrl.isNotEmpty) ? configServerUrl : null);
    final agentId = _lastAgentId ?? ((configAgentId != null && configAgentId.isNotEmpty) ? configAgentId : null);

    if (serverUrl == null || agentId == null) {
      return null;
    }

    return _ConnectionContext(serverUrl: serverUrl, agentId: agentId);
  }

  String? _resolveAuthTokenForReconnect() {
    final liveToken = _authProvider?.currentToken?.token;
    if (liveToken != null && liveToken.trim().isNotEmpty) {
      _sessionAuthInvalid = false;
      return _lastAuthToken = liveToken.trim();
    }

    if (_sessionAuthInvalid) {
      return null;
    }

    final configToken = _configProvider?.currentConfig?.authToken;
    if (configToken != null && configToken.trim().isNotEmpty) {
      return _lastAuthToken = configToken.trim();
    }

    return _lastAuthToken;
  }

  Future<bool> _isHubReachableForReconnect(
    String serverUrl, {
    required String stage,
  }) async {
    final checkHubAvailabilityUseCase = _checkHubAvailabilityUseCase;
    if (checkHubAvailabilityUseCase == null) {
      return true;
    }
    final isReachable = await checkHubAvailabilityUseCase(serverUrl);
    if (!isReachable) {
      AppLogger.info('resilience: hub_probe_offline stage=$stage server=$serverUrl');
    }
    return isReachable;
  }

  bool get _shouldEscalateToHardRelogin {
    if (!_effectiveHardReloginRecoveryEnabled) {
      return false;
    }
    if (_hardReloginAttemptedInCycle) {
      return false;
    }
    return _consecutiveReconnectFailures >= _effectiveHardReloginFailureThreshold;
  }

  Future<String?> _attemptHardRelogin(_ConnectionContext context) async {
    _hardReloginAttemptedInCycle = true;
    final coordinator = _hubRecoveryAuthCoordinator;
    final authProvider = _authProvider;
    if (coordinator == null || authProvider == null) {
      _status = ConnectionStatus.error;
      _error = 'Authentication provider unavailable for automatic relogin';
      _cancelPersistentRetryTimer();
      return null;
    }

    AppLogger.warning(
      'resilience: escalating to automatic hard relogin after $_consecutiveReconnectFailures failures',
    );
    await authProvider.logout();

    final reloginResult = await coordinator.loginWithStoredCredentials(
      context.serverUrl,
      context.agentId,
    );
    return reloginResult.fold(
      (token) {
        authProvider.restoreToken(token);
        _sessionAuthInvalid = false;
        _consecutiveReconnectFailures = 0;
        return _lastAuthToken = token.token.trim();
      },
      (failure) {
        authProvider.setRecoveryError(failure.toDisplayMessage());
        _sessionAuthInvalid = true;
        _status = ConnectionStatus.error;
        _error = failure.toDisplayMessage();
        _cancelPersistentRetryTimer();
        return null;
      },
    );
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
