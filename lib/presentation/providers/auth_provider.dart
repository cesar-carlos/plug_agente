import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._hubSessionCoordinator);

  final HubSessionCoordinator _hubSessionCoordinator;

  AuthStatus _status = AuthStatus.unauthenticated;
  String _error = '';
  AuthToken? _currentToken;
  String? _activeConfigId;
  bool _suppressAuthSuccessModalOnce = false;

  AuthStatus get status => _status;
  String get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  AuthToken? get currentToken => _currentToken;
  String? get activeConfigId => _activeConfigId;

  AuthToken? currentTokenForConfig(String? configId) {
    return _matchesConfig(configId) ? _currentToken : null;
  }

  AuthToken? tokenForConfig(String? configId) {
    return currentTokenForConfig(configId);
  }

  bool isAuthenticatedForConfig(String? configId) {
    return _status == AuthStatus.authenticated && currentTokenForConfig(configId) != null;
  }

  Future<void> login({
    required String configId,
    required String serverUrl,
    required AuthCredentials credentials,
  }) async {
    final previousToken = _currentToken;
    final previousStatus = _status;
    final previousConfigId = _activeConfigId;
    final normalizedConfigId = _normalizeConfigId(configId);

    _status = AuthStatus.authenticating;
    _error = '';
    notifyListeners();

    final result = await _hubSessionCoordinator.login(
      configId: configId,
      serverUrl: serverUrl,
      credentials: credentials,
    );

    await result.fold(
      (token) async {
        _currentToken = token;
        _activeConfigId = normalizedConfigId;
        _status = AuthStatus.authenticated;
        _error = '';
        AppLogger.info('Login successful');
      },
      (failure) {
        _currentToken = previousToken;
        _activeConfigId = previousConfigId;
        _status = previousToken == null ? AuthStatus.error : previousStatus;
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Login failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    notifyListeners();
  }

  Future<void> refreshToken({
    required String configId,
    required String serverUrl,
  }) async {
    final scopedToken = currentTokenForConfig(configId);
    if (scopedToken?.refreshToken == null) {
      _currentToken = null;
      _activeConfigId = null;
      _status = AuthStatus.unauthenticated;
      _error = 'No refresh token available';
      notifyListeners();
      return;
    }

    final result = await _hubSessionCoordinator.refreshSession(
      serverUrl,
      configId: configId,
      currentToken: scopedToken,
    );

    await result.fold(
      (token) async {
        _currentToken = token;
        _activeConfigId = _normalizeConfigId(configId);
        _status = AuthStatus.authenticated;
        _error = '';
        AppLogger.info('Token refreshed successfully');
      },
      (failure) {
        _currentToken = null;
        _activeConfigId = null;
        _status = AuthStatus.unauthenticated;
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Token refresh failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    notifyListeners();
  }

  Future<void> logout({
    String? configId,
    bool clearStoredSession = false,
  }) async {
    _currentToken = null;
    _activeConfigId = null;
    _status = AuthStatus.unauthenticated;
    _error = '';
    notifyListeners();
    AppLogger.info('User logged out');
    if (clearStoredSession && configId != null && configId.trim().isNotEmpty) {
      final result = await _hubSessionCoordinator.clearStoredSession(configId);
      result.fold(
        (_) {},
        (failure) {
          _error = failure.toDisplayMessage();
          AppLogger.error(
            'Failed to clear stored session: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          notifyListeners();
        },
      );
    }
  }

  void restoreToken(
    AuthToken token, {
    bool authenticated = true,
    String? configId,
    bool silent = false,
  }) {
    final priorAuthenticated = _status == AuthStatus.authenticated;
    _currentToken = token;
    _activeConfigId = _normalizeConfigId(configId) ?? _activeConfigId;
    _status = authenticated ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    _error = '';
    if (silent && !priorAuthenticated && _status == AuthStatus.authenticated) {
      _suppressAuthSuccessModalOnce = true;
    }
    notifyListeners();
  }

  /// When [restoreToken] was called with `silent: true`, the next pull returns
  /// `true` once so UI can skip the "authenticated successfully" modal.
  bool pullSuppressAuthSuccessModalOnce() {
    if (!_suppressAuthSuccessModalOnce) {
      return false;
    }
    _suppressAuthSuccessModalOnce = false;
    return true;
  }

  void setRecoveryError(String message) {
    _currentToken = null;
    _activeConfigId = null;
    _status = AuthStatus.unauthenticated;
    _error = message;
    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  bool _matchesConfig(String? configId) {
    final normalizedConfigId = _normalizeConfigId(configId);
    return normalizedConfigId != null && _activeConfigId != null && normalizedConfigId == _activeConfigId;
  }

  String? _normalizeConfigId(String? configId) {
    final normalized = configId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
