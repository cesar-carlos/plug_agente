import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/boot/startup_auto_session_initializer.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class _MockHubSessionCoordinator extends Mock implements HubSessionCoordinator {}

class _MockConnectionProvider extends Mock with ChangeNotifier implements ConnectionProvider {}

class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class _MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AuthToken(
        token: 'fallback-token',
        refreshToken: 'fallback-refresh',
      ),
    );
  });

  group('boot coordination', () {
    late _MockHubSessionCoordinator hubSessionCoordinator;
    late _MockConnectionProvider connectionProvider;
    late _MockAuthProvider authProvider;
    late _MockConfigProvider configProvider;
    final bootstrapCallOrder = <String>[];

    setUp(() {
      hubSessionCoordinator = _MockHubSessionCoordinator();
      connectionProvider = _MockConnectionProvider();
      authProvider = _MockAuthProvider();
      configProvider = _MockConfigProvider();
      bootstrapCallOrder.clear();

      when(() => configProvider.isLoading).thenReturn(false);
      when(() => configProvider.currentConfig).thenReturn(_configWithStoredCredentials());
      when(() => configProvider.getConnectionString()).thenReturn('dsn=local');
      when(() => connectionProvider.isConnected).thenReturn(false);
      when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
      when(() => connectionProvider.isReconnecting).thenReturn(false);
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      ).thenAnswer((_) async {
        bootstrapCallOrder.add('hub');
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
        () => connectionProvider.connect(
          any(),
          any(),
          configId: any(named: 'configId'),
          authToken: any(named: 'authToken'),
          recoverOnFailure: any(named: 'recoverOnFailure'),
        ),
      ).thenAnswer((_) async => const Success(unit));
      when(
        () => authProvider.restoreToken(
          any(),
          configId: any(named: 'configId'),
          silent: any(named: 'silent'),
        ),
      ).thenReturn(null);
    });

    testWidgets('awaits deferred bootstrap before Hub auto-connect', (tester) async {
      final deferredBootstrapGate = Completer<void>();

      Future<DeferredBootPhaseOutcome> runDeferredBootstrap() async {
        bootstrapCallOrder.add('deferred-start');
        await deferredBootstrapGate.future;
        bootstrapCallOrder.add('deferred-end');
        return const DeferredBootPhaseOutcome.success();
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
          ],
          child: StartupAutoSessionInitializer(
            hubSessionCoordinator: hubSessionCoordinator,
            runDeferredBootstrapBeforeConnect: runDeferredBootstrap,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(bootstrapCallOrder, <String>['deferred-start']);
      verifyNever(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );

      await tester.runAsync(() async {
        deferredBootstrapGate.complete();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(bootstrapCallOrder, containsAll(<String>['deferred-start', 'deferred-end', 'hub']));
      expect(
        bootstrapCallOrder.indexOf('deferred-end'),
        lessThan(bootstrapCallOrder.indexOf('hub')),
      );
      verify(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).called(1);
    });

    testWidgets('skips Hub auto-connect after critical deferred bootstrap failure', (tester) async {
      Future<DeferredBootPhaseOutcome> runDeferredBootstrap() async {
        return const DeferredBootPhaseOutcome(
          schedulerStarted: false,
          hadCriticalFailure: true,
        );
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
          ],
          child: StartupAutoSessionInitializer(
            hubSessionCoordinator: hubSessionCoordinator,
            runDeferredBootstrapBeforeConnect: runDeferredBootstrap,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      verifyNever(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
      verifyNever(
        () => connectionProvider.connect(
          any(),
          any(),
          configId: any(named: 'configId'),
          authToken: any(named: 'authToken'),
          recoverOnFailure: any(named: 'recoverOnFailure'),
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
