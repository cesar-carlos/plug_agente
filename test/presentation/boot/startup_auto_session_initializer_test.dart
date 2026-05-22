import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
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
  group('StartupAutoSessionInitializer', () {
    late _MockHubSessionCoordinator hubSessionCoordinator;
    late _MockConnectionProvider connectionProvider;
    late _MockAuthProvider authProvider;
    late _MockConfigProvider configProvider;

    setUp(() {
      hubSessionCoordinator = _MockHubSessionCoordinator();
      connectionProvider = _MockConnectionProvider();
      authProvider = _MockAuthProvider();
      configProvider = _MockConfigProvider();

      when(() => configProvider.isLoading).thenReturn(false);
      when(() => configProvider.currentConfig).thenReturn(_configWithStoredCredentials());
      when(() => configProvider.getConnectionString()).thenReturn('dsn=local');
      when(() => connectionProvider.isConnected).thenReturn(false);
      when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
      when(() => connectionProvider.isReconnecting).thenReturn(false);
    });

    testWidgets('should start persistent recovery when bootstrap fails transiently', (tester) async {
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).thenAnswer((_) async => Failure(domain_errors.NetworkFailure('Hub offline')));

      await _pumpInitializer(
        tester,
        hubSessionCoordinator: hubSessionCoordinator,
        connectionProvider: connectionProvider,
        authProvider: authProvider,
        configProvider: configProvider,
      );

      verify(
        () => connectionProvider.startPersistentHubRecovery(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).called(1);
      verifyNever(() => authProvider.setRecoveryError(any()));
    });

    testWidgets('should expose recovery error when bootstrap failure is terminal', (tester) async {
      when(
        () => hubSessionCoordinator.bootstrapAutoSession(
          configId: 'config-1',
          serverUrl: 'https://hub.test',
          agentId: 'agent-1',
        ),
      ).thenAnswer((_) async => Failure(domain_errors.ValidationFailure('Invalid credentials')));

      await _pumpInitializer(
        tester,
        hubSessionCoordinator: hubSessionCoordinator,
        connectionProvider: connectionProvider,
        authProvider: authProvider,
        configProvider: configProvider,
      );

      verify(() => authProvider.setRecoveryError('Invalid credentials')).called(1);
      verifyNever(
        () => connectionProvider.startPersistentHubRecovery(
          configId: any(named: 'configId'),
          serverUrl: any(named: 'serverUrl'),
          agentId: any(named: 'agentId'),
        ),
      );
    });
  });
}

Future<void> _pumpInitializer(
  WidgetTester tester, {
  required HubSessionCoordinator hubSessionCoordinator,
  required ConnectionProvider connectionProvider,
  required AuthProvider authProvider,
  required ConfigProvider configProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
      ],
      child: StartupAutoSessionInitializer(
        hubSessionCoordinator: hubSessionCoordinator,
        child: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
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
