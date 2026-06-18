import 'package:checks/checks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';

class _MockSessionCoordinator extends Mock implements HubSessionCoordinator {}

class _MockAuthBridge extends Mock implements IHubRecoveryAuthBridge {}

void main() {
  late _MockSessionCoordinator sessionCoordinator;
  late _MockAuthBridge authBridge;
  late HubAccessTokenRenewer renewer;

  setUpAll(() {
    registerFallbackValue(
      const AuthToken(token: 'fallback-access', refreshToken: 'fallback-refresh'),
    );
  });

  setUp(() {
    sessionCoordinator = _MockSessionCoordinator();
    authBridge = _MockAuthBridge();
    renewer = HubAccessTokenRenewer(
      sessionCoordinator,
      HubAccessTokenRefreshGate(minInterval: Duration.zero),
    );
    renewer.bindAuthBridge(authBridge);
  });

  test('should succeed after auth bridge is bound', () async {
    renewer.clearAuthBridge();

    when(() => authBridge.currentTokenForConfig(any())).thenReturn(
      const AuthToken(token: 'access-1', refreshToken: 'refresh-1'),
    );
    when(
      () => authBridge.refreshSession(
        any(),
        configId: any(named: 'configId'),
        currentToken: any(named: 'currentToken'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'access-2', refreshToken: 'refresh-2'),
      ),
    );
    when(
      () => authBridge.restoreToken(
        any(),
        configId: any(named: 'configId'),
        silent: any(named: 'silent'),
      ),
    ).thenReturn(null);

    renewer.bindAuthBridge(authBridge);

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.token).equals('access-2');
  });

  test('should fail when auth bridge is not bound', () async {
    renewer.clearAuthBridge();

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
    );

    check(result.isError()).isTrue();
    check(result.exceptionOrNull()).isA<domain.ConfigurationFailure>();
  });

  test('should renew using bridge token with refresh', () async {
    when(() => authBridge.currentTokenForConfig(any())).thenReturn(
      const AuthToken(token: 'access-1', refreshToken: 'refresh-1'),
    );
    when(
      () => authBridge.refreshSession(
        any(),
        configId: any(named: 'configId'),
        currentToken: any(named: 'currentToken'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'access-2', refreshToken: 'refresh-2'),
      ),
    );
    when(
      () => authBridge.restoreToken(
        any(),
        configId: any(named: 'configId'),
        silent: any(named: 'silent'),
      ),
    ).thenReturn(null);

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
      configId: 'cfg-1',
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.token).equals('access-2');
    verify(
      () => authBridge.refreshSession(
        'https://hub.example',
        configId: 'cfg-1',
        currentToken: any(named: 'currentToken'),
      ),
    ).called(1);
  });

  test('should load persisted refresh when bridge token lacks refresh', () async {
    when(() => authBridge.currentTokenForConfig('cfg-1')).thenReturn(
      const AuthToken(token: 'access-1', refreshToken: ''),
    );
    when(() => sessionCoordinator.loadPersistedTokenPair('cfg-1')).thenAnswer(
      (_) async => const AuthToken(token: 'access-1', refreshToken: 'persisted-refresh'),
    );
    when(
      () => authBridge.refreshSession(
        any(),
        configId: any(named: 'configId'),
        currentToken: any(named: 'currentToken'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'access-2', refreshToken: 'refresh-2'),
      ),
    );
    when(
      () => authBridge.restoreToken(
        any(),
        configId: any(named: 'configId'),
        silent: any(named: 'silent'),
      ),
    ).thenReturn(null);

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
      configId: 'cfg-1',
    );

    check(result.isSuccess()).isTrue();
    verify(() => sessionCoordinator.loadPersistedTokenPair('cfg-1')).called(1);
  });

  test('should fail when no refresh token is available', () async {
    when(() => authBridge.currentTokenForConfig(any())).thenReturn(
      const AuthToken(token: 'access-1', refreshToken: ''),
    );
    when(() => sessionCoordinator.loadPersistedTokenPair(any())).thenAnswer((_) async => null);

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
      configId: 'cfg-1',
    );

    check(result.isError()).isTrue();
    check(result.exceptionOrNull()).isA<domain.ConfigurationFailure>();
    verifyNever(
      () => authBridge.refreshSession(
        any(),
        configId: any(named: 'configId'),
        currentToken: any(named: 'currentToken'),
      ),
    );
  });

  test('should propagate refresh session failure', () async {
    when(() => authBridge.currentTokenForConfig(any())).thenReturn(
      const AuthToken(token: 'access-1', refreshToken: 'refresh-1'),
    );
    when(
      () => authBridge.refreshSession(
        any(),
        configId: any(named: 'configId'),
        currentToken: any(named: 'currentToken'),
      ),
    ).thenAnswer(
      (_) async => Failure(domain.NetworkFailure.withContext(message: 'offline')),
    );

    final result = await renewer.renew(
      serverUrl: 'https://hub.example',
      accessToken: 'access-1',
    );

    check(result.isError()).isTrue();
    check(result.exceptionOrNull()).isA<domain.NetworkFailure>();
  });
}
