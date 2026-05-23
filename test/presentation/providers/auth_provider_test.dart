import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockHubSessionCoordinator extends Mock implements HubSessionCoordinator {}

void main() {
  const configId = 'cfg-1';
  const serverUrl = 'server_url';

  setUpAll(() {
    registerFallbackValue(AuthCredentials.test());
    registerFallbackValue(
      const AuthToken(
        token: 'test_token',
        refreshToken: 'test_refresh_token',
      ),
    );
  });

  group('AuthProvider', () {
    late AuthProvider provider;
    late MockHubSessionCoordinator mockHubSessionCoordinator;

    setUp(() {
      mockHubSessionCoordinator = MockHubSessionCoordinator();
      provider = AuthProvider(mockHubSessionCoordinator);
    });

    group('login', () {
      test('should set authenticated status when login succeeds', () async {
        const token = AuthToken(
          token: 'test_token',
          refreshToken: 'test_refresh_token',
        );
        when(
          () => mockHubSessionCoordinator.login(
            configId: configId,
            serverUrl: serverUrl,
            credentials: any(named: 'credentials'),
          ),
        ).thenAnswer((_) async => const Success(token));

        await provider.login(
          configId: configId,
          serverUrl: serverUrl,
          credentials: AuthCredentials.test(),
        );

        expect(provider.isAuthenticated, isTrue);
        expect(provider.status, equals(AuthStatus.authenticated));
        expect(provider.currentToken, token);
        expect(provider.activeConfigId, configId);
        expect(provider.isAuthenticatedForConfig(configId), isTrue);
        expect(provider.error, isEmpty);
      });

      test('should set error status when login fails', () async {
        final failure = domain_errors.ValidationFailure('Invalid credentials');
        when(
          () => mockHubSessionCoordinator.login(
            configId: configId,
            serverUrl: serverUrl,
            credentials: any(named: 'credentials'),
          ),
        ).thenAnswer((_) async => Failure(failure));

        await provider.login(
          configId: configId,
          serverUrl: serverUrl,
          credentials: AuthCredentials.test(),
        );

        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.error));
        expect(provider.currentToken, isNull);
        expect(provider.activeConfigId, isNull);
        expect(provider.error, contains('Invalid credentials'));
      });

      test('should clear any in-memory token when persistence fails in coordinator', () async {
        final failure = domain_errors.DatabaseFailure('Save failed');
        when(
          () => mockHubSessionCoordinator.login(
            configId: configId,
            serverUrl: serverUrl,
            credentials: any(named: 'credentials'),
          ),
        ).thenAnswer((_) async => Failure(failure));

        await provider.login(
          configId: configId,
          serverUrl: serverUrl,
          credentials: AuthCredentials.test(),
        );

        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.error));
        expect(provider.currentToken, isNull);
        expect(provider.activeConfigId, isNull);
        expect(provider.error, contains('Save failed'));
      });

      test('should set authenticating status during login', () async {
        final completer = Completer<Result<AuthToken>>();
        when(
          () => mockHubSessionCoordinator.login(
            configId: configId,
            serverUrl: serverUrl,
            credentials: any(named: 'credentials'),
          ),
        ).thenAnswer((_) => completer.future);

        final future = provider.login(
          configId: configId,
          serverUrl: serverUrl,
          credentials: AuthCredentials.test(),
        );

        expect(provider.status, equals(AuthStatus.authenticating));
        expect(provider.isAuthenticated, isFalse);

        completer.complete(
          Failure(domain_errors.ValidationFailure('test')),
        );
        await future;
      });
    });

    group('refreshToken', () {
      test('should refresh token successfully', () async {
        const oldToken = AuthToken(
          token: 'old_token',
          refreshToken: 'old_refresh',
        );
        const newToken = AuthToken(
          token: 'new_token',
          refreshToken: 'new_refresh',
        );
        provider.restoreToken(oldToken, configId: configId);
        when(
          () => mockHubSessionCoordinator.refreshSession(
            serverUrl,
            configId: configId,
            currentToken: oldToken,
          ),
        ).thenAnswer((_) async => const Success(newToken));

        await provider.refreshToken(
          configId: configId,
          serverUrl: serverUrl,
        );

        expect(provider.isAuthenticated, isTrue);
        expect(provider.status, equals(AuthStatus.authenticated));
        expect(provider.currentToken?.token, equals('new_token'));
        expect(provider.activeConfigId, configId);
      });

      test('should handle refresh failure and clear token', () async {
        const oldToken = AuthToken(
          token: 'old_token',
          refreshToken: 'old_refresh',
        );
        provider.restoreToken(oldToken, configId: configId);
        when(
          () => mockHubSessionCoordinator.refreshSession(
            serverUrl,
            configId: configId,
            currentToken: oldToken,
          ),
        ).thenAnswer(
          (_) async => Failure(domain_errors.NetworkFailure('Network error')),
        );

        await provider.refreshToken(
          configId: configId,
          serverUrl: serverUrl,
        );

        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.currentToken, isNull);
        expect(provider.activeConfigId, isNull);
        expect(provider.error, contains('Network error'));
      });

      test('should set error when no refresh token available', () async {
        expect(provider.currentToken?.refreshToken, isNull);

        await provider.refreshToken(
          configId: configId,
          serverUrl: serverUrl,
        );

        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.error, equals('No refresh token available'));
      });

      test('should not expose token for a different config id', () async {
        const oldToken = AuthToken(
          token: 'old_token',
          refreshToken: 'old_refresh',
        );
        provider.restoreToken(oldToken, configId: configId);

        expect(provider.currentTokenForConfig('cfg-2'), isNull);
        expect(provider.isAuthenticatedForConfig('cfg-2'), isFalse);
      });
    });

    group('logout', () {
      test('should clear token and status', () async {
        const token = AuthToken(
          token: 'test_token',
          refreshToken: 'test_refresh',
        );
        provider.restoreToken(token, configId: configId);

        await provider.logout();

        expect(provider.isAuthenticated, isFalse);
        expect(provider.status, equals(AuthStatus.unauthenticated));
        expect(provider.currentToken, isNull);
        expect(provider.activeConfigId, isNull);
        expect(provider.error, isEmpty);
      });

      test('should clear stored session by config id', () async {
        provider.restoreToken(
          const AuthToken(token: 't', refreshToken: 'r'),
          configId: configId,
        );
        when(
          () => mockHubSessionCoordinator.clearStoredSession(configId),
        ).thenAnswer((_) async => const Success(unit));

        await provider.logout(
          configId: configId,
          clearStoredSession: true,
        );

        verify(
          () => mockHubSessionCoordinator.clearStoredSession(configId),
        ).called(1);
      });
    });

    group('restoreToken', () {
      test('silent transition arms pullSuppressAuthSuccessModalOnce once', () {
        const token = AuthToken(token: 't', refreshToken: 'r');
        provider.restoreToken(token, configId: configId, silent: true);

        expect(provider.pullSuppressAuthSuccessModalOnce(), isTrue);
        expect(provider.pullSuppressAuthSuccessModalOnce(), isFalse);
      });

      test('silent restore when already authenticated does not arm suppression', () {
        const first = AuthToken(token: 't1', refreshToken: 'r1');
        const second = AuthToken(token: 't2', refreshToken: 'r2');
        provider.restoreToken(first, configId: configId);
        provider.restoreToken(second, configId: configId, silent: true);

        expect(provider.pullSuppressAuthSuccessModalOnce(), isFalse);
      });
    });

    group('clearError', () {
      test('should clear error message', () async {
        when(
          () => mockHubSessionCoordinator.login(
            configId: configId,
            serverUrl: 'url',
            credentials: any(named: 'credentials'),
          ),
        ).thenAnswer(
          (_) async => Failure(domain_errors.ValidationFailure('Test error')),
        );

        await provider.login(
          configId: configId,
          serverUrl: 'url',
          credentials: AuthCredentials.test(),
        );
        expect(provider.error, isNotEmpty);

        provider.clearError();

        expect(provider.error, isEmpty);
      });
    });
  });
}
