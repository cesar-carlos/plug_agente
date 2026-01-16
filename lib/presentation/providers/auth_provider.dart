import 'package:flutter/foundation.dart';

import '../../application/use_cases/login_user.dart';
import '../../application/use_cases/refresh_auth_token.dart';
import '../../application/use_cases/save_auth_token.dart';
import '../../core/logger/app_logger.dart';
import '../../domain/entities/auth_token.dart';
import '../../domain/errors/failures.dart';
import '../../domain/value_objects/auth_credentials.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthProvider extends ChangeNotifier {
  final LoginUser _loginUseCase;
  final RefreshAuthToken _refreshUseCase;
  final SaveAuthToken _saveUseCase;

  AuthProvider(
    this._loginUseCase,
    this._refreshUseCase,
    this._saveUseCase,
  );

  AuthStatus _status = AuthStatus.unauthenticated;
  String _error = '';
  AuthToken? _currentToken;

  AuthStatus get status => _status;
  String get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  AuthToken? get currentToken => _currentToken;

  Future<void> login(String serverUrl, AuthCredentials credentials) async {
    _status = AuthStatus.authenticating;
    _error = '';
    notifyListeners();

    try {
      final result = await _loginUseCase(serverUrl, credentials);
      
      result.fold(
        (token) async {
          _currentToken = token;
          final saveResult = await _saveUseCase(token);
          saveResult.fold(
            (_) {
              _status = AuthStatus.authenticated;
              AppLogger.info('Login successful');
            },
            (failure) {
              _status = AuthStatus.error;
              final failureMessage = failure is Failure
                  ? failure.message
                  : failure.toString();
              _error = 'Failed to save token: $failureMessage';
              AppLogger.error('Failed to save token: $failureMessage');
            },
          );
        },
        (failure) {
          _status = AuthStatus.error;
          final failureMessage = failure is Failure
              ? failure.message
              : failure.toString();
          _error = failureMessage;
          AppLogger.error('Login failed: $failureMessage');
        },
      );
    } catch (e) {
      _status = AuthStatus.error;
      _error = 'Unexpected error: $e';
      AppLogger.error('Unexpected error during login: $e');
    }

    notifyListeners();
  }

  Future<void> refreshToken(String serverUrl) async {
    if (_currentToken?.refreshToken == null) {
      _status = AuthStatus.unauthenticated;
      _error = 'No refresh token available';
      notifyListeners();
      return;
    }

    try {
      final result = await _refreshUseCase(serverUrl, _currentToken!.refreshToken);
      
      result.fold(
        (token) async {
          _currentToken = token;
          final saveResult = await _saveUseCase(token);
          saveResult.fold(
            (_) {
              _status = AuthStatus.authenticated;
              AppLogger.info('Token refreshed successfully');
            },
            (failure) {
              _status = AuthStatus.unauthenticated;
              final failureMessage = failure is Failure
                  ? failure.message
                  : failure.toString();
              _error = 'Failed to save token: $failureMessage';
              AppLogger.error('Failed to save token: $failureMessage');
            },
          );
        },
        (failure) {
          _status = AuthStatus.unauthenticated;
          final failureMessage = failure is Failure
              ? failure.message
              : failure.toString();
          _error = failureMessage;
          AppLogger.error('Token refresh failed: $failureMessage');
        },
      );
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _error = 'Unexpected error: $e';
      AppLogger.error('Unexpected error during token refresh: $e');
    }

    notifyListeners();
  }

  void logout() {
    _currentToken = null;
    _status = AuthStatus.unauthenticated;
    _error = '';
    notifyListeners();
    AppLogger.info('User logged out');
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }
}
