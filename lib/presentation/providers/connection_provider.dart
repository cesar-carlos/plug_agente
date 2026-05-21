import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/transport_reconnect_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/reconnect_delay_calculator.dart';
import 'package:plug_agente/domain/entities/config.dart';
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
  negotiating,
  connected,
  reconnecting,
  error,
}

/// Finer-grained UI label while [ConnectionStatus.reconnecting] (hub resilience).
enum HubRecoveryUiHint {
  none,
  signingIn,
  connectingSocket,
  awaitingHubReachability,
}

class ConnectionProvider extends ChangeNotifier {
  ConnectionProvider(
    this._connectToHubUseCase,
    this._testDbConnectionUseCase,
    this._checkOdbcDriverUseCase, {
    HubSessionCoordinator? hubSessionCoordinator,
    HubSessionCoordinator? hubRecoveryAuthCoordinator,
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
    Duration? hubTokenRefreshMinInterval,
    Duration? hubHardReloginCooldown,
    Random? random,
  }) : _checkHubAvailabilityUseCase = checkHubAvailabilityUseCase,
       _hubSessionCoordinator = hubSessionCoordinator ?? hubRecoveryAuthCoordinator,
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
       _hubTokenRefreshMinIntervalOverride = hubTokenRefreshMinInterval,
       _hubHardReloginCooldownOverride = hubHardReloginCooldown,
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
    if (hubTokenRefreshMinInterval != null && hubTokenRefreshMinInterval.inMicroseconds < 0) {
      throw ArgumentError.value(
        hubTokenRefreshMinInterval,
        'hubTokenRefreshMinInterval',
        'must not be negative',
      );
    }
    if (hubHardReloginCooldown != null && hubHardReloginCooldown.inMicroseconds < 0) {
      throw ArgumentError.value(
        hubHardReloginCooldown,
        'hubHardReloginCooldown',
        'must not be negative',
      );
    }
  }
  final CheckHubAvailability? _checkHubAvailabilityUseCase;
  final HubSessionCoordinator? _hubSessionCoordinator;
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
  String? _lastConfigId;
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
  DateTime? _lastHubRefreshHttpCompletedAt;
  int _reconnectQuietFailureLogCount = 0;
  String? _resilienceRecoveryId;
  DateTime? _lastHardReloginEndedAt;
  HubRecoveryUiHint _hubRecoveryUiHint = HubRecoveryUiHint.none;

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
  final Duration? _hubTokenRefreshMinIntervalOverride;
  final Duration? _hubHardReloginCooldownOverride;
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

  Duration get _effectiveHubTokenRefreshMinInterval =>
      _hubTokenRefreshMinIntervalOverride ?? ConnectionConstants.hubTokenRefreshMinInterval;

  Duration get _effectiveHubHardReloginCooldown =>
      _hubHardReloginCooldownOverride ?? ConnectionConstants.hubHardReloginCooldown;

  bool get _effectiveHardReloginRecoveryEnabled =>
      _featureFlags?.enableHubHardReloginRecovery ?? _enableHardReloginRecoveryOverride;

  int get _effectiveHardReloginFailureThreshold {
    final configured = _featureFlags?.hubHardReloginFailureThreshold ?? _hardReloginFailureThresholdOverride;
    return configured.clamp(_hardReloginMinThreshold, _hardReloginMaxThreshold);
  }

  ConnectionStatus get status => _status;
  String get error => _error;
  bool get isDbConnected => _isDbConnected;
  String? get activeConfigId => _lastConfigId;

  HubRecoveryUiHint get hubRecoveryUiHint => _hubRecoveryUiHint;

  void _setHubRecoveryUiHint(HubRecoveryUiHint hint) {
    if (_hubRecoveryUiHint == hint) {
      return;
    }
    _hubRecoveryUiHint = hint;
    notifyListeners();
  }

  void _clearHubRecoveryUiHint() {
    _setHubRecoveryUiHint(HubRecoveryUiHint.none);
  }

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
  bool get isConnectingOrNegotiating =>
      _status == ConnectionStatus.connecting || _status == ConnectionStatus.negotiating;
  bool get isCheckingDriver => _isCheckingDriver;

  String _resilienceLogPrefix() {
    final id = _resilienceRecoveryId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return 'recovery_id=$id ';
  }

  void _syncTransportResilienceLogContext() {
    final transport = _transportClientOverride;
    if (transport != null) {
      transport.setResilienceLogContext(_resilienceRecoveryId);
      return;
    }
    if (getIt.isRegistered<ITransportClient>()) {
      getIt<ITransportClient>().setResilienceLogContext(_resilienceRecoveryId);
    }
  }

  void _beginResilienceRecovery() {
    if (_resilienceRecoveryId != null && _resilienceRecoveryId!.isNotEmpty) {
      _syncTransportResilienceLogContext();
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = _random?.nextInt(0x100000) ?? 0;
    _resilienceRecoveryId = 'rec-${stamp}_${entropy.toRadixString(16)}';
    _syncTransportResilienceLogContext();
  }

  void _clearResilienceRecovery() {
    _resilienceRecoveryId = null;
    _syncTransportResilienceLogContext();
  }

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) async {
    _cancelPersistentRetryTimer();
    _persistentFailureCount = 0;
    _consecutiveReconnectFailures = 0;
    _hardReloginAttemptedInCycle = false;
    _sessionAuthInvalid = false;
    _lastHubRefreshHttpCompletedAt = null;
    _reconnectQuietFailureLogCount = 0;
    _clearResilienceRecovery();
    _clearHubRecoveryUiHint();
    _isDisconnectRequested = false;
    final resolvedConfigId = _resolveActiveConfigId(configId);
    if (_lastConfigId != null && _lastConfigId != resolvedConfigId) {
      _lastAuthToken = null;
    }
    _lastConfigId = resolvedConfigId;
    _lastServerUrl = serverUrl;
    _lastAgentId = agentId;
    _lastAuthToken = _normalizeToken(authToken) ?? _lastAuthToken;

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

    final finalResult = result.fold<Result<void>>(
      (_) {
        if (_isDisconnectRequested) {
          return const Success(unit);
        }
        _cancelPersistentRetryTimer();
        _clearHubRecoveryUiHint();
        _status = ConnectionStatus.negotiating;
        _error = '';
        AppLogger.info('Connected to hub transport; waiting for protocol negotiation');
        return const Success(unit);
      },
      (failure) {
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          return Failure(failure);
        }
        if (_isReconnecting || _status == ConnectionStatus.reconnecting) {
          AppLogger.warning(
            'Initial connect failure ignored because hub recovery is already in progress: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          return Failure(failure);
        }
        if (recoverOnFailure && _resolveConnectionContext() != null) {
          _beginResilienceRecovery();
          _status = ConnectionStatus.reconnecting;
          _error = '';
          _clearHubRecoveryUiHint();
          AppLogger.warning(
            'Initial hub connect failed; entering persistent recovery: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          _startPersistentRetry();
          return Failure(failure);
        }
        _status = ConnectionStatus.error;
        _error = failure.toDisplayMessage();
        _clearHubRecoveryUiHint();
        AppLogger.error(
          'Failed to connect to hub: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        return Failure(failure);
      },
    );

    notifyListeners();
    return finalResult;
  }

  Future<void> disconnect() async {
    _isDisconnectRequested = true;
    _clearResilienceRecovery();
    _clearHubRecoveryUiHint();
    _cancelPersistentRetryTimer();
    _hardReloginAttemptedInCycle = false;
    _consecutiveReconnectFailures = 0;
    _lastHubRefreshHttpCompletedAt = null;
    _reconnectQuietFailureLogCount = 0;
    _lastAuthToken = null;
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
    // need to refresh - otherwise `_handleConnectionError` fires `_onTokenExpired` and we
    // never rotate JWT until user logs out/in manually.
    if (_isReconnecting) {
      final context = _resolveConnectionContext();
      if (context != null) {
        AppLogger.warning(
          'Hub reported authentication failure during reconnect; refreshing token',
        );
        AppLogger.debug(
          'resilience: ${_resilienceLogPrefix()}token_refresh event=during_reconnect_burst '
          'agent_id=${context.agentId}',
        );
        await _tryRefreshToken(context);
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
      _beginResilienceRecovery();
      final transportClient = _transportClientOverride ?? getIt<ITransportClient>();
      await transportClient.disconnect();

      final context = _resolveConnectionContext();
      if (context == null) {
        _clearResilienceRecovery();
        _status = ConnectionStatus.error;
        _error = 'Connection context unavailable for token refresh';
        _clearHubRecoveryUiHint();
        AppLogger.error('Cannot refresh token without connection context');
      } else {
        final refreshResult = await _tryRefreshToken(context);
        final reconnectToken = switch (refreshResult.kind) {
          _TokenRefreshResultKind.refreshed => refreshResult.token,
          _TokenRefreshResultKind.skippedByCooldown => _resolveAuthTokenForReconnect(),
          _TokenRefreshResultKind.transientFailure => _resolveAuthTokenForReconnect(),
          _TokenRefreshResultKind.terminalFailure => null,
        };
        if (reconnectToken == null) {
          _clearResilienceRecovery();
          _status = ConnectionStatus.error;
          _error = 'Failed to refresh authentication token';
          _clearHubRecoveryUiHint();
          AppLogger.error('Token refresh failed during reconnect policy');
        } else {
          final connected = await _attemptReconnect(
            context.serverUrl,
            context.agentId,
            authToken: reconnectToken,
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
      _clearResilienceRecovery();
      _clearHubRecoveryUiHint();
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
      AppLogger.debug(
        'resilience: ${_resilienceLogPrefix()}reconnect event=handler_skipped '
        'reconnecting=$_isReconnecting disconnect_requested=$_isDisconnectRequested',
      );
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
        _clearHubRecoveryUiHint();
        AppLogger.error('Missing server URL or agent ID for reconnection');
      } else {
        _beginResilienceRecovery();
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}reconnect event=full_recovery_started '
          'agent_id=${context.agentId}',
        );
        final connected = await _recoverConnection(
          context,
          proactiveHardReloginBeforeSocket: true,
        );
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          _error = '';
          AppLogger.info('Reconnection loop cancelled by user disconnect');
          _clearResilienceRecovery();
          return;
        }
        if (connected) {
          AppLogger.info(
            'resilience: ${_resilienceLogPrefix()}reconnect event=burst_recovery_complete '
            'agent_id=${context.agentId}',
          );
        }
        if (!connected) {
          if (_isDisconnectRequested) {
            _clearResilienceRecovery();
            return;
          }
          _status = ConnectionStatus.reconnecting;
          _error = '';
          AppLogger.warning('Connection burst recovery exhausted; starting persistent hub retry');
          _startPersistentRetry();
        }
      }
    } on Exception catch (error, stackTrace) {
      _clearResilienceRecovery();
      _clearHubRecoveryUiHint();
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

  Future<void> _disconnectTransportForRecovery() async {
    try {
      final client =
          _transportClientOverride ?? (getIt.isRegistered<ITransportClient>() ? getIt<ITransportClient>() : null);
      if (client == null) {
        return;
      }
      final result = await client.disconnect();
      result.fold(
        (_) {},
        (failure) {
          AppLogger.warning(
            'resilience: ${_resilienceLogPrefix()}transport_disconnect_during_recovery '
            'message=$failure',
          );
        },
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'resilience: ${_resilienceLogPrefix()}transport_disconnect_during_recovery event=exception',
        error,
        stackTrace,
      );
    }
  }

  Future<String?> _executeHardRelogin(
    _ConnectionContext context, {
    required String logSummary,
    bool ignoreCooldown = false,
  }) async {
    if (!ignoreCooldown && _isHardReloginCooldownActive()) {
      final last = _lastHardReloginEndedAt;
      final remainingMs = last == null
          ? 0
          : (_effectiveHubHardReloginCooldown - DateTime.now().difference(last)).inMilliseconds;
      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}hard_relogin event=skipped_cooldown '
        'remaining_ms=${remainingMs.clamp(0, 86400000)} '
        'agent_id=${context.agentId}',
      );
      return null;
    }

    final coordinator = _hubSessionCoordinator;
    final authProvider = _authProvider;
    if (coordinator == null || authProvider == null) {
      _clearResilienceRecovery();
      _status = ConnectionStatus.error;
      _error = 'Authentication provider unavailable for automatic relogin';
      _cancelPersistentRetryTimer();
      _clearHubRecoveryUiHint();
      return null;
    }

    try {
      _setHubRecoveryUiHint(HubRecoveryUiHint.signingIn);
      AppLogger.warning(
        'resilience: ${_resilienceLogPrefix()}hard_relogin event=started $logSummary '
        'agent_id=${context.agentId}',
      );
      await authProvider.logout(configId: context.configId);

      final reloginResult = await coordinator.loginWithStoredCredentials(
        context.serverUrl,
        context.agentId,
        configId: context.configId,
      );
      return reloginResult.fold(
        (token) {
          authProvider.restoreToken(token, configId: context.configId);
          _sessionAuthInvalid = false;
          _consecutiveReconnectFailures = 0;
          return _lastAuthToken = token.token.trim();
        },
        (Object failure) {
          unawaited(coordinator.clearStoredSession(context.configId));
          authProvider.setRecoveryError(failure.toDisplayMessage());
          _lastAuthToken = null;
          _sessionAuthInvalid = true;
          _status = ConnectionStatus.error;
          _error = failure.toDisplayMessage();
          _cancelPersistentRetryTimer();
          _clearResilienceRecovery();
          _clearHubRecoveryUiHint();
          return null;
        },
      );
    } finally {
      _lastHardReloginEndedAt = DateTime.now();
    }
  }

  Future<bool> _recoverConnection(
    _ConnectionContext context, {
    bool proactiveHardReloginBeforeSocket = false,
  }) async {
    AppLogger.info(
      'resilience: ${_resilienceLogPrefix()}burst_recovery event=started max_attempts=$_maxReconnectAttempts '
      'agent_id=${context.agentId}',
    );
    var didProactiveHardRelogin = false;
    if (proactiveHardReloginBeforeSocket && _effectiveHardReloginRecoveryEnabled) {
      final coordinator = _hubSessionCoordinator;
      final authProvider = _authProvider;
      if (coordinator != null && authProvider != null) {
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}burst_recovery event=pre_socket_full_relogin '
          'agent_id=${context.agentId}',
        );
        await _disconnectTransportForRecovery();
        _hardReloginAttemptedInCycle = true;
        await _executeHardRelogin(
          context,
          logSummary: 'trigger=before_socket_recovery',
          ignoreCooldown: true,
        );
        if (_isDisconnectRequested) {
          return false;
        }
        if (_status == ConnectionStatus.error) {
          return false;
        }
        didProactiveHardRelogin = true;
      }
    }

    var authToken = _resolveAuthTokenForReconnect();
    if (!didProactiveHardRelogin) {
      final refreshResult = await _tryRefreshToken(context);
      if (refreshResult.kind == _TokenRefreshResultKind.refreshed) {
        authToken = refreshResult.token;
      }
    }
    for (var attempt = 1; attempt <= _maxReconnectAttempts && !_isDisconnectRequested; attempt++) {
      final delay = _computeReconnectDelay(attempt);
      if (delay > Duration.zero) {
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}reconnect_delay_ms attempt=$attempt '
          'delay_ms=${delay.inMilliseconds} agent_id=${context.agentId}',
        );
        await Future<void>.delayed(delay);
      }

      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}connect_attempt attempt=$attempt agent_id=${context.agentId}',
      );
      final hubReachable = await _isHubReachableForReconnect(
        context.serverUrl,
        stage: 'burst',
      );
      if (!hubReachable) {
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_unreachable_skip_connect attempt=$attempt agent_id=${context.agentId}',
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
        final hardReloginToken = await _attemptHardRelogin(context, ignoreCooldown: true);
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
        final refreshResult = await _tryRefreshToken(context);
        if (refreshResult.kind == _TokenRefreshResultKind.refreshed &&
            refreshResult.token != null) {
          authToken = refreshResult.token;
        }
      }
    }

    AppLogger.warning(
      'resilience: ${_resilienceLogPrefix()}burst_recovery event=exhausted max_attempts=$_maxReconnectAttempts '
      'agent_id=${context.agentId}',
    );
    return false;
  }

  Future<bool> _attemptReconnect(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage = true,
  }) async {
    if (_status == ConnectionStatus.reconnecting || _isReconnecting) {
      _setHubRecoveryUiHint(HubRecoveryUiHint.connectingSocket);
    }
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
        _reconnectQuietFailureLogCount = 0;
        _status = ConnectionStatus.negotiating;
        _error = '';
        _lastServerUrl = serverUrl;
        _lastAgentId = agentId;
        if (authToken != null && authToken.trim().isNotEmpty) {
          _lastAuthToken = authToken.trim();
        }
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_connect event=transport_succeeded agent_id=$agentId',
        );
        _clearHubRecoveryUiHint();
        return true;
      },
      (Object failure) {
        _consecutiveReconnectFailures++;
        _status = ConnectionStatus.reconnecting;
        _error = recordErrorMessage ? failure.toDisplayMessage() : '';
        if (recordErrorMessage) {
          AppLogger.warning(
            'Reconnection attempt failed: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
        } else {
          _reconnectQuietFailureLogCount++;
          const stride = ConnectionConstants.hubReconnectFailureLogThrottleStride;
          if (_reconnectQuietFailureLogCount == 1 || _reconnectQuietFailureLogCount % stride == 0) {
            AppLogger.warning(
              'resilience: ${_resilienceLogPrefix()}reconnect event=attempt_failed_throttled '
              'count=$_reconnectQuietFailureLogCount stride=$stride '
              'display=${failure.toDisplayMessage()}',
              failure.toTechnicalMessage(),
            );
          }
        }
        _clearHubRecoveryUiHint();
        return false;
      },
    );
  }

  bool _isHardReloginCooldownActive() {
    final gap = _effectiveHubHardReloginCooldown;
    if (gap <= Duration.zero) {
      return false;
    }
    final last = _lastHardReloginEndedAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) < gap;
  }

  void _bumpPersistentReconnectFailure(
    _ConnectionContext context, {
    required String reason,
  }) {
    if (_effectiveHubPersistentRetryMaxFailedTicks <= 0) {
      return;
    }
    _persistentFailureCount++;
    AppLogger.info(
      'resilience: ${_resilienceLogPrefix()}hub_persistent_retry_failure '
      'count=$_persistentFailureCount '
      'max=$_effectiveHubPersistentRetryMaxFailedTicks '
      'reason=$reason '
      'agent_id=${context.agentId}',
    );
    if (_persistentFailureCount >= _effectiveHubPersistentRetryMaxFailedTicks) {
      _cancelPersistentRetryTimer();
      _status = ConnectionStatus.error;
      _error = ConnectionConstants.hubPersistentRetryExhaustedMessage;
      AppLogger.warning(
        'resilience: ${_resilienceLogPrefix()}persistent_retry event=exhausted '
        'failures=$_persistentFailureCount '
        'max=$_effectiveHubPersistentRetryMaxFailedTicks '
        'agent_id=${context.agentId}',
      );
      _clearResilienceRecovery();
      _clearHubRecoveryUiHint();
      notifyListeners();
    }
  }

  void _handleHubLifecycle(HubLifecycleNotification notification) {
    if (_isDisconnectRequested) {
      return;
    }
    switch (notification) {
      case HubTransportDisconnected(:final reason):
        if (_status == ConnectionStatus.disconnected) {
          return;
        }
        _beginResilienceRecovery();
        final serverInitiated = isHubIoServerInitiatedDisconnect(reason);
        final disconnectLine =
            'resilience: ${_resilienceLogPrefix()}hub_transport event=socket_disconnected '
            'kind=${serverInitiated ? "io_server_disconnect" : "client_or_network"} '
            'reason=${reason ?? "unknown"} '
            'agent_id=${_lastAgentId ?? "?"}';
        AppLogger.debug(disconnectLine);
        _status = ConnectionStatus.reconnecting;
        _error = '';
        notifyListeners();
      case HubTransportReconnectAttempt(:final attemptNumber):
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_socket_reconnect_attempt attempt=$attemptNumber '
          'status=${_status.name}',
        );
        if (_status == ConnectionStatus.connected || _status == ConnectionStatus.negotiating) {
          _status = ConnectionStatus.reconnecting;
          _error = '';
          notifyListeners();
        }
      case HubProtocolReady():
        if (_status != ConnectionStatus.negotiating &&
            _status != ConnectionStatus.reconnecting &&
            _status != ConnectionStatus.connected) {
          AppLogger.debug(
            'resilience: ${_resilienceLogPrefix()}hub_transport event=protocol_ready_ignored '
            'status=${_status.name} agent_id=${_lastAgentId ?? "?"}',
          );
          return;
        }
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_transport event=protocol_ready '
          'agent_id=${_lastAgentId ?? "?"}',
        );
        _clearResilienceRecovery();
        _cancelPersistentRetryTimer();
        _clearHubRecoveryUiHint();
        _status = ConnectionStatus.connected;
        _error = '';
        notifyListeners();
      case HubTransportAutoReconnectSucceeded():
        if (_status != ConnectionStatus.negotiating &&
            _status != ConnectionStatus.reconnecting &&
            _status != ConnectionStatus.connected) {
          AppLogger.debug(
            'resilience: ${_resilienceLogPrefix()}hub_transport event=auto_reconnect_capabilities_ok_ignored '
            'status=${_status.name} agent_id=${_lastAgentId ?? "?"}',
          );
          return;
        }
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_transport event=auto_reconnect_capabilities_ok '
          'agent_id=${_lastAgentId ?? "?"}',
        );
        _clearResilienceRecovery();
        _cancelPersistentRetryTimer();
        _clearHubRecoveryUiHint();
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
    final ctx = _resolveConnectionContext();
    AppLogger.warning(
      'resilience: ${_resilienceLogPrefix()}persistent_retry event=started '
      'interval_ms=${_effectiveHubPersistentRetryInterval.inMilliseconds} '
      'max_failed_ticks=$_effectiveHubPersistentRetryMaxFailedTicks '
      'agent_id=${ctx?.agentId ?? "?"}',
    );
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
      _hardReloginAttemptedInCycle = false;
      if (_isDisconnectRequested) {
        _cancelPersistentRetryTimer();
        return;
      }
      final context = _resolveConnectionContext();
      if (context == null) {
        AppLogger.warning(
          'resilience: ${_resilienceLogPrefix()}persistent_retry event=context_missing '
          'reason=missing_server_url_or_agent_id',
        );
        _clearResilienceRecovery();
        _cancelPersistentRetryTimer();
        return;
      }
      _persistentRetryTickCount++;
      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}hub_persistent_retry_tick tick=$_persistentRetryTickCount '
        'agent_id=${context.agentId}',
      );
      if (_persistentRetryTickCount % _tokenRefreshIntervalAttempts == 0) {
        await _tryRefreshToken(context);
      }
      final hubReachable = await _isHubReachableForReconnect(
        context.serverUrl,
        stage: 'persistent',
      );
      if (!hubReachable) {
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_unreachable_skip_connect tick=$_persistentRetryTickCount agent_id=${context.agentId}',
        );
        _setHubRecoveryUiHint(HubRecoveryUiHint.awaitingHubReachability);
        _bumpPersistentReconnectFailure(context, reason: TransportReconnectConstants.hubUnreachableReason);
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
        if (ok) {
          AppLogger.info(
            'resilience: ${_resilienceLogPrefix()}persistent_retry event=hub_reconnect_succeeded '
            'tick=$_persistentRetryTickCount agent_id=${context.agentId}',
          );
        }
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
      _bumpPersistentReconnectFailure(context, reason: TransportReconnectConstants.socketReconnectFailedReason);
    } finally {
      _persistentRetryInFlight = false;
    }
  }

  @override
  void dispose() {
    _cancelPersistentRetryTimer();
    _clearHubRecoveryUiHint();
    super.dispose();
  }

  Future<_TokenRefreshResult> _tryRefreshToken(_ConnectionContext context) async {
    final coordinator = _hubSessionCoordinator;
    final authProvider = _authProvider;
    if (coordinator == null || authProvider == null) {
      _sessionAuthInvalid = true;
      return const _TokenRefreshResult.terminalFailure();
    }

    final minGap = _effectiveHubTokenRefreshMinInterval;
    final last = _lastHubRefreshHttpCompletedAt;
    if (minGap > Duration.zero && last != null && DateTime.now().difference(last) < minGap) {
      AppLogger.debug(
        'resilience: ${_resilienceLogPrefix()}token_refresh event=skipped_min_interval '
        'min_interval_ms=${minGap.inMilliseconds} '
        'elapsed_ms=${DateTime.now().difference(last).inMilliseconds}',
      );
      return const _TokenRefreshResult.skippedByCooldown();
    }

    final refreshResult = await coordinator.refreshSession(
      context.serverUrl,
      configId: context.configId,
      currentToken: authProvider.currentTokenForConfig(context.configId),
    );
    return refreshResult.fold(
      (token) {
        authProvider.restoreToken(token, configId: context.configId);
        _sessionAuthInvalid = false;
        _lastHubRefreshHttpCompletedAt = DateTime.now();
        final normalizedToken = token.token.trim();
        _lastAuthToken = normalizedToken;
        return _TokenRefreshResult.refreshed(normalizedToken);
      },
      (Object failure) {
        _lastHubRefreshHttpCompletedAt = DateTime.now();
        if (failure is domain_errors.Failure && failure.isTransient) {
          AppLogger.warning(
            'resilience: ${_resilienceLogPrefix()}token_refresh event=transient_failure '
            'display=${failure.toDisplayMessage()} '
            'technical=${failure.toTechnicalMessage()}',
          );
          return const _TokenRefreshResult.transientFailure();
        }
        authProvider.setRecoveryError(failure.toDisplayMessage());
        _lastAuthToken = null;
        _sessionAuthInvalid = true;
        return const _TokenRefreshResult.terminalFailure();
      },
    );
  }

  _ConnectionContext? _resolveConnectionContext() {
    final config = _resolveTrackedConfig();
    final configServerUrl = config?.serverUrl.trim();
    final configAgentId = config?.agentId.trim();
    final configId = _lastConfigId ?? config?.id;
    final serverUrl =
        _lastServerUrl ?? ((configServerUrl != null && configServerUrl.isNotEmpty) ? configServerUrl : null);
    final agentId = _lastAgentId ?? ((configAgentId != null && configAgentId.isNotEmpty) ? configAgentId : null);

    if (configId == null || serverUrl == null || agentId == null) {
      return null;
    }

    return _ConnectionContext(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
    );
  }

  String? _resolveAuthTokenForReconnect() {
    final liveToken = _normalizeToken(
      _authProvider?.currentTokenForConfig(_lastConfigId)?.token,
    );
    if (liveToken != null) {
      _sessionAuthInvalid = false;
      return _lastAuthToken = liveToken;
    }

    if (_sessionAuthInvalid) {
      return null;
    }

    final configToken = _normalizeToken(_resolveTrackedConfig()?.authToken);
    if (configToken != null) {
      return _lastAuthToken = configToken;
    }

    return _lastAuthToken;
  }

  Config? _resolveTrackedConfig() {
    final config = _configProvider?.currentConfig;
    if (config == null) {
      return null;
    }

    final configId = _lastConfigId?.trim();
    if (configId == null || configId.isEmpty || config.id == configId) {
      return config;
    }

    return null;
  }

  String _resolveActiveConfigId(String? candidateConfigId) {
    final normalized = candidateConfigId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }

    final currentConfigId = _configProvider?.currentConfig?.id.trim();
    if (currentConfigId != null && currentConfigId.isNotEmpty) {
      return currentConfigId;
    }

    return _lastConfigId ?? 'unknown-config';
  }

  String? _normalizeToken(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<bool> _isHubReachableForReconnect(
    String serverUrl, {
    required String stage,
  }) async {
    final checkHubAvailabilityUseCase = _checkHubAvailabilityUseCase;
    if (checkHubAvailabilityUseCase == null) {
      return true;
    }
    final sw = Stopwatch()..start();
    final isReachable = await checkHubAvailabilityUseCase(serverUrl);
    sw.stop();
    final elapsedMs = sw.elapsedMilliseconds;
    if (elapsedMs >= ConnectionConstants.hubAvailabilityProbeSlowLogThresholdMs) {
      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}hub_probe_slow elapsed_ms=$elapsedMs stage=$stage server=$serverUrl '
        'reachable=$isReachable',
      );
    }
    if (!isReachable) {
      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}hub_probe_offline stage=$stage server=$serverUrl elapsed_ms=$elapsedMs',
      );
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

  Future<String?> _attemptHardRelogin(
    _ConnectionContext context, {
    bool ignoreCooldown = false,
  }) async {
    _hardReloginAttemptedInCycle = true;
    return _executeHardRelogin(
      context,
      logSummary: 'trigger=consecutive_failures failures=$_consecutiveReconnectFailures',
      ignoreCooldown: ignoreCooldown,
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
    required this.configId,
    required this.serverUrl,
    required this.agentId,
  });

  final String configId;
  final String serverUrl;
  final String agentId;
}

enum _TokenRefreshResultKind {
  refreshed,
  skippedByCooldown,
  transientFailure,
  terminalFailure,
}

class _TokenRefreshResult {
  const _TokenRefreshResult._({
    required this.kind,
    this.token,
  });

  const _TokenRefreshResult.refreshed(String token)
    : this._(kind: _TokenRefreshResultKind.refreshed, token: token);

  const _TokenRefreshResult.skippedByCooldown()
    : this._(kind: _TokenRefreshResultKind.skippedByCooldown);

  const _TokenRefreshResult.transientFailure()
    : this._(kind: _TokenRefreshResultKind.transientFailure);

  const _TokenRefreshResult.terminalFailure()
    : this._(kind: _TokenRefreshResultKind.terminalFailure);

  final _TokenRefreshResultKind kind;
  final String? token;
}
