import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockLoginUser extends Mock implements LoginUser {}

class MockRefreshAuthToken extends Mock implements RefreshAuthToken {}

class MockSaveAuthToken extends Mock implements SaveAuthToken {}

void main() {
  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(AuthCredentials.test());
    registerFallbackValue(const AuthToken(
      token: 'test_token',
      refreshToken: 'test_refresh_token',
    ));
  });

  group('AuthProvider', () {
    late AuthProvider provider;
    late MockLoginUser mockLoginUseCase;
    late MockRefreshAuthToken mockRefreshUseCase;
    late MockSaveAuthToken mockSaveUseCase;

    setUp(() {
      mockLoginUseCase = MockLoginUser();
      mockRefreshUseCase = MockRefreshAuthToken();
      mockSaveUseCase = MockSaveAuthToken();
      provider = AuthProvider(
        mockLoginUseCase,
        mockRefreshUseCase,
        mockSaveUseCase,
      );
    });

    group('login', () {
      test('should set authenticated status when login succeeds', () async {
        // Arrange
        const token = AuthToken(
          token: 'test_token',
          refreshToken: 'test_refresh_token',
        );
        when(() => mockLoginUseCase('server_url', any()))
            .thenAnswer((_) async => const Success(token));
        when(() => mockSaveUseCase(token))
            .thenAnswer((_) async => const Success(unit));

        // Act
        await provider.login('server_url', AuthCredentials.test());

        // Assert
        expect(provider.isAuthenticated, isTrue);
        expect(provider.status, equals(AuthStatus.authenticated));
        expect(provider.error, isEmpty);
      });

      test('should set error status when login fails with ValidationFailure',
          () async {
        // Arrange
        final failure = domain_errors.ValidationFailure('Invalid credentials');
        when(() => mockLoginUseCase('server_url', any()))
            .thenAnswer((_) async => Failure(failure));

        // Act
        await provider.login('server_url', AuthCredentials.test());

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.error));
        expect(provider.error, equals('Invalid credentials'));
      });

      test('should set error status when login fails with NetworkFailure',
          () async {
        // Arrange
        final failure = domain_errors.NetworkFailure('Connection timeout');
        when(() => mockLoginUseCase('server_url', any()))
            .thenAnswer((_) async => Failure(failure));

        // Act
        await provider.login('server_url', AuthCredentials.test());

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.error));
        expect(provider.error, equals('Connection timeout'));
      });

      test('should set error status when saving token fails', () async {
        // Arrange
        const token = AuthToken(
          token: 'test_token',
          refreshToken: 'test_refresh_token',
        );
        when(() => mockLoginUseCase('server_url', any()))
            .thenAnswer((_) async => const Success(token));
        when(() => mockSaveUseCase(token))
            .thenAnswer((_) async => Failure(domain_errors.DatabaseFailure('Save failed')));

        // Act
        await provider.login('server_url', AuthCredentials.test());

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.error));
        expect(provider.error, contains('Failed to save token'));
      });

      test('should set authenticating status during login', () async {
        // Arrange
        final completer = Completer<Result<AuthToken>>();
        when(() => mockLoginUseCase('server_url', any()))
            .thenAnswer((_) => completer.future);

        // Act
        final future = provider.login('server_url', AuthCredentials.test());

        // Assert - status deve ser authenticating imediatamente
        expect(provider.status, equals(AuthStatus.authenticating));
        expect(provider.isAuthenticated, isFalse);

        // Cleanup
        completer.complete(Failure(domain_errors.ValidationFailure('test')));
        await future;
      });
    });

    group('refreshToken', () {
      test('should refresh token successfully', () async {
        // Arrange - first login to set a token
        const oldToken = AuthToken(
          token: 'old_token',
          refreshToken: 'old_refresh',
        );
        const newToken = AuthToken(
          token: 'new_token',
          refreshToken: 'new_refresh',
        );

        when(() => mockLoginUseCase(any(), any()))
            .thenAnswer((_) async => const Success(oldToken));
        when(() => mockSaveUseCase(any()))
            .thenAnswer((_) async => const Success(unit));
        await provider.login('server_url', AuthCredentials.test());

        // Now set up refresh mocks
        when(() => mockRefreshUseCase('server_url', 'old_refresh'))
            .thenAnswer((_) async => const Success(newToken));

        // Act
        await provider.refreshToken('server_url');

        // Assert
        expect(provider.isAuthenticated, isTrue);
        expect(provider.status, equals(AuthStatus.authenticated));
        expect(provider.currentToken?.token, equals('new_token'));
      });

      test('should handle refresh failure', () async {
        // Arrange - first login to set a token
        const oldToken = AuthToken(
          token: 'old_token',
          refreshToken: 'old_refresh',
        );

        when(() => mockLoginUseCase(any(), any()))
            .thenAnswer((_) async => const Success(oldToken));
        when(() => mockSaveUseCase(any()))
            .thenAnswer((_) async => const Success(unit));
        await provider.login('server_url', AuthCredentials.test());

        // Now set up refresh to fail
        when(() => mockRefreshUseCase('server_url', 'old_refresh'))
            .thenAnswer((_) async => Failure(domain_errors.NetworkFailure('Network error')));

        // Act
        await provider.refreshToken('server_url');

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.error, equals('Network error'));
      });

      test('should set error when no refresh token available', () async {
        // Arrange - provider sem token (no login yet)
        expect(provider.currentToken?.refreshToken, isNull);

        // Act
        await provider.refreshToken('server_url');

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.error, equals('No refresh token available'));
      });
    });

    group('logout', () {
      test('should clear token and status', () async {
        // Arrange - login to set token
        const token = AuthToken(
          token: 'test_token',
          refreshToken: 'test_refresh',
        );

        when(() => mockLoginUseCase(any(), any()))
            .thenAnswer((_) async => const Success(token));
        when(() => mockSaveUseCase(any()))
            .thenAnswer((_) async => const Success(unit));
        await provider.login('server_url', AuthCredentials.test());

        // Verify authenticated state before logout
        expect(provider.isAuthenticated, isTrue);
        expect(provider.currentToken, isNotNull);

        // Act
        provider.logout();

        // Assert
        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.currentToken, isNull);
        expect(provider.error, isEmpty);
      });
    });

    group('clearError', () {
      test('should clear error message', () async {
        // Arrange - set error through login failure
        final failure = domain_errors.ValidationFailure('Test error');
        when(() => mockLoginUseCase(any(), any()))
            .thenAnswer((_) async => Failure(failure));

        // Act - trigger error then clear it
        await provider.login('url', AuthCredentials.test());
        expect(provider.error, isNotEmpty); // Verify error was set

        provider.clearError();

        // Assert
        expect(provider.error, isEmpty);
      });
    });
  });
}
