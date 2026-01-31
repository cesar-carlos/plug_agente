import 'package:flutter/foundation.dart';

import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._loginUseCase, this._refreshUseCase, this._saveUseCase);
  final LoginUser _loginUseCase;
  final RefreshAuthToken _refreshUseCase;
  final SaveAuthToken _saveUseCase;

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

    final result = await _loginUseCase(serverUrl, credentials);

    await result.fold(
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
            _error = 'Failed to save token: ${failure.toUserMessage()}';
            AppLogger.error(
              'Failed to save token: ${failure.toUserMessage()}',
            );
          },
        );
      },
      (failure) {
        _status = AuthStatus.error;
        _error = failure.toUserMessage();
        AppLogger.error('Login failed: $_error');
      },
    );

    notifyListeners();
  }

  Future<void> refreshToken(String serverUrl) async {
    if (_currentToken?.refreshToken == null) {
      _status = AuthStatus.unauthenticated;
      _error = 'No refresh token available';
      notifyListeners();
      return;
    }

    final result = await _refreshUseCase(
      serverUrl,
      _currentToken!.refreshToken,
    );

    await result.fold(
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
            _error = 'Failed to save token: ${failure.toUserMessage()}';
            AppLogger.error('Failed to save token: ${failure.toUserMessage()}');
          },
        );
      },
      (failure) {
        _status = AuthStatus.unauthenticated;
        _error = failure.toUserMessage();
        AppLogger.error('Token refresh failed: $_error');
      },
    );

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
