import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/ports/i_startup_session_auth_sink.dart';
import 'package:plug_agente/application/ports/i_startup_session_config_source.dart';
import 'package:plug_agente/application/ports/i_startup_session_connection_gateway.dart';
import 'package:plug_agente/application/ports/startup_session_ports.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/services/startup_session_orchestrator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

class _MockHubSessionCoordinator extends Mock implements HubSessionCoordinator {}

class _MockConfigSource extends Mock implements IStartupSessionConfigSource {}

class _MockAuthSink extends Mock implements IStartupSessionAuthSink {}

class _MockConnectionGateway extends Mock implements IStartupSessionConnectionGateway {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AuthToken(
        token: 'fallback-token',
        refreshToken: 'fallback-refresh',
      ),
    );
  });

  late _MockHubSessionCoordinator hubSessionCoordinator;
  late _MockConfigSource configSource;
  late _MockAuthSink authSink;
  late _MockConnectionGateway connectionGateway;
  late StartupSessionOrchestrator orchestrator;

  setUp(() {
    hubSessionCoordinator = _MockHubSessionCoordinator();
    configSource = _MockConfigSource();
    authSink = _MockAuthSink();
    connectionGateway = _MockConnectionGateway();
    orchestrator = StartupSessionOrchestrator(
      hubSessionCoordinator: hubSessionCoordinator,
      ports: StartupSessionPorts(
        config: configSource,
        auth: authSink,
        connection: connectionGateway,
      ),
    );

    when(() => configSource.isLoading).thenReturn(false);
    when(() => configSource.currentConfig).thenReturn(_configWithStoredCredentials());
    when(() => connectionGateway.isConnected).thenReturn(false);
    when(() => connectionGateway.status).thenReturn(ConnectionStatus.disconnected);
    when(() => connectionGateway.isReconnecting).thenReturn(false);
  });

  group('StartupSessionOrchestrator', () {
    test('skips when config is still loading', () async {
      when(() => configSource.isLoading).thenReturn(true);

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.skipped);
      verifyNever(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
    });

    test('skips when config is missing', () async {
      when(() => configSource.currentConfig).thenReturn(null);

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.skipped);
    });

    test('skips when startup credentials are incomplete', () async {
      when(() => configSource.currentConfig).thenReturn(
        _configWithStoredCredentials().copyWith(authUsername: '', authPassword: ''),
      );

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.skipped);
    });

    test('completes without bootstrap when hub is already connecting', () async {
      when(() => connectionGateway.status).thenReturn(ConnectionStatus.connecting);

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.completed);
      verifyNever(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
    });

    test('bootstraps, restores token silently, and connects on success', () async {
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).thenAnswer(
        (_) async => const Success(
          HubBootstrapSession(
            token: AuthToken(
              token: 'access-token',
              refreshToken: 'refresh-token',
            ),
            source: HubBootstrapSource.persistedToken,
          ),
        ),
      );
      when(
        () => connectionGateway.connect(
          'https://hub.test',
          'agent-1',
          configId: 'config-1',
          authToken: 'access-token',
          recoverOnFailure: true,
        ),
      ).thenAnswer((_) async => const Success(unit));

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.completed);
      verify(
        () => authSink.restoreToken(
          const AuthToken(
            token: 'access-token',
            refreshToken: 'refresh-token',
          ),
          configId: 'config-1',
          silent: true,
        ),
      ).called(1);
    });

    test('starts persistent recovery when bootstrap fails transiently', () async {
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      ).thenAnswer((_) async => Failure(domain_errors.NetworkFailure('Hub offline')));

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.skipped);
      verify(
        () => connectionGateway.startPersistentHubRecovery(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).called(1);
      verifyNever(() => authSink.setRecoveryError(any()));
    });

    test('returns bootstrapFailed and exposes recovery error on terminal bootstrap failure', () async {
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      ).thenAnswer(
        (_) async => Failure(domain_errors.ValidationFailure('Invalid credentials')),
      );

      final result = await orchestrator.run();

      expect(result, StartupSessionFlowResult.bootstrapFailed);
      verify(() => authSink.setRecoveryError('Invalid credentials')).called(1);
      verifyNever(
        () => connectionGateway.startPersistentHubRecovery(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
    });

    test('awaits deferred bootstrap before hub auto-connect', () async {
      final callOrder = <String>[];

      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      ).thenAnswer((_) async {
        callOrder.add('hub');
        return const Success(
          HubBootstrapSession(
            token: AuthToken(
              token: 'access-token',
              refreshToken: 'refresh-token',
            ),
            source: HubBootstrapSource.persistedToken,
          ),
        );
      });
      when(
        () => connectionGateway.connect(
          any(),
          any(),
          configId: any(named: 'configId'),
          authToken: any(named: 'authToken'),
          recoverOnFailure: any(named: 'recoverOnFailure'),
        ),
      ).thenAnswer((_) async {
        callOrder.add('connect');
        return const Success(unit);
      });

      final result = await orchestrator.run(
        runDeferredBootstrapBeforeConnect: () async {
          callOrder.add('deferred');
          return const DeferredBootPhaseOutcome.success();
        },
      );

      expect(result, StartupSessionFlowResult.completed);
      expect(callOrder, <String>['deferred', 'hub', 'connect']);
    });

    test('returns deferredBootstrapFailed when deferred bootstrap reports critical failure', () async {
      final result = await orchestrator.run(
        runDeferredBootstrapBeforeConnect: () async {
          return const DeferredBootPhaseOutcome(
            schedulerStarted: false,
            hadCriticalFailure: true,
          );
        },
      );

      expect(result, StartupSessionFlowResult.deferredBootstrapFailed);
      verifyNever(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
    });
  });
}

Config _configWithStoredCredentials() {
  final now = DateTime(2026);
  return Config(
    id: 'config-1',
    serverUrl: 'https://hub.test',
    agentId: 'agent-1',
    authUsername: 'agent@example.com',
    authPassword: 'secret',
    driverName: 'sqlserver',
    odbcDriverName: 'ODBC Driver',
    connectionString: 'dsn=local',
    username: 'db-user',
    databaseName: 'db',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );
}
