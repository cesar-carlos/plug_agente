import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/bootstrap/odbc_runtime_reload_teardown_service.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_application_runtime_reset_port.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/bootstrap/odbc_runtime_reloader.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockStreamingSessionCache extends Mock implements IOdbcStreamingSessionCache {}

class _MockSqlInvestigationCollector extends Mock implements ISqlInvestigationCollector {}

class _MockQueuedDatabaseGateway extends Mock implements QueuedDatabaseGateway {}

class _MockApplicationRuntimeResetPort extends Mock implements IOdbcApplicationRuntimeResetPort {}

class _MockTransportClient extends Mock implements ITransportClient {}

class _FakeHubShutdownPort implements IHubConnectionShutdownPort {
  _FakeHubShutdownPort(this.onDisconnect);

  final Future<void> Function() onDisconnect;

  @override
  Future<void> disconnectForShutdown() => onDisconnect();
}

class _FakeOdbcWorkerLocator implements odbc.ServiceLocator {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('OdbcRuntimeReloader', () {
    late GetIt getIt;
    late _MockQueuedDatabaseGateway queuedGateway;
    late _MockStreamingSessionCache streamingCache;
    late _MockConnectionPool connectionPool;
    late _MockSqlInvestigationCollector investigationCollector;
    late _MockApplicationRuntimeResetPort applicationResetPort;
    late _MockTransportClient transportClient;
    late HubConnectionShutdownRegistry hubShutdownRegistry;
    late AppShutdownCoordinator shutdownCoordinator;
    late AgentActionRuntimeStateGuard agentActionGuard;
    late List<String> teardownEvents;
    late OdbcRuntimeReloader reloader;

    setUp(() {
      getIt = GetIt.asNewInstance();
      queuedGateway = _MockQueuedDatabaseGateway();
      streamingCache = _MockStreamingSessionCache();
      connectionPool = _MockConnectionPool();
      investigationCollector = _MockSqlInvestigationCollector();
      applicationResetPort = _MockApplicationRuntimeResetPort();
      transportClient = _MockTransportClient();
      hubShutdownRegistry = HubConnectionShutdownRegistry();
      agentActionGuard = AgentActionRuntimeStateGuard();
      teardownEvents = <String>[];

      shutdownCoordinator = AppShutdownCoordinator(
        hubConnectionShutdownRegistry: hubShutdownRegistry,
        transportClient: transportClient,
      );

      getIt
        ..registerSingleton<AgentActionRuntimeStateGuard>(agentActionGuard)
        ..registerSingleton<IDatabaseGateway>(queuedGateway)
        ..registerSingleton<IOdbcStreamingSessionCache>(streamingCache)
        ..registerSingleton<IConnectionPool>(connectionPool)
        ..registerSingleton<ISqlInvestigationCollector>(investigationCollector)
        ..registerSingleton<AppShutdownCoordinator>(shutdownCoordinator)
        ..registerSingleton<ITransportClient>(transportClient);

      when(() => queuedGateway.disposeGracefully()).thenAnswer((_) async {
        teardownEvents.add('dispose_sql_queue');
        return const Success(unit);
      });
      when(() => streamingCache.drainCachedSessions()).thenAnswer((_) async {
        teardownEvents.add('drain_streaming_cache');
        return const Success(unit);
      });
      when(() => connectionPool.closeAll()).thenAnswer((_) async {
        teardownEvents.add('close_pool');
        return const Success(unit);
      });
      when(() => investigationCollector.clear()).thenAnswer((_) {
        teardownEvents.add('clear_investigation');
      });
      when(() => applicationResetPort.resetForOdbcRuntimeReload()).thenAnswer((_) async {
        teardownEvents.add('application_reset');
      });

      reloader = OdbcRuntimeReloader(
        getIt: getIt,
        odbcWorkerLocator: _FakeOdbcWorkerLocator(),
        applicationRuntimeResetPort: applicationResetPort,
        teardownPort: OdbcRuntimeReloadTeardownService(getIt: getIt),
      );
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('drains SQL queue and streaming cache before hub disconnect and pool close', () async {
      hubShutdownRegistry.bind(
        _FakeHubShutdownPort(() async {
          teardownEvents.add('hub_disconnect');
        }),
      );

      final result = await reloader.reload();

      expect(result, isFalse);
      expect(
        teardownEvents.take(5),
        <String>[
          'clear_investigation',
          'dispose_sql_queue',
          'drain_streaming_cache',
          'hub_disconnect',
          'close_pool',
        ],
      );
      verifyNever(() => transportClient.disconnect());
      verifyInOrder([
        () => queuedGateway.disposeGracefully(),
        () => streamingCache.drainCachedSessions(),
        () => connectionPool.closeAll(),
      ]);
    });

    test('marks agent actions draining during reload teardown', () async {
      hubShutdownRegistry.bind(
        _FakeHubShutdownPort(() async {
          teardownEvents.add('hub_disconnect');
        }),
      );

      await reloader.reload();

      expect(
        agentActionGuard.snapshot.reason,
        isNot(AgentActionRuntimeStateConstants.odbcRuntimeReloadReason),
      );
      expect(teardownEvents, contains('dispose_sql_queue'));
    });
  });
}
