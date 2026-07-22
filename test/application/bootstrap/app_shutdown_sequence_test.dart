import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_sequence.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockStreamingSessionCache extends Mock implements IOdbcStreamingSessionCache {}

class _MockQueuedDatabaseGateway extends Mock implements QueuedDatabaseGateway {}

void main() {
  late GetIt getIt;
  late _MockStreamingSessionCache streamingCache;
  late _MockConnectionPool connectionPool;
  late _MockQueuedDatabaseGateway queuedGateway;
  late List<String> shutdownEvents;

  setUp(() {
    getIt = GetIt.asNewInstance();
    streamingCache = _MockStreamingSessionCache();
    connectionPool = _MockConnectionPool();
    queuedGateway = _MockQueuedDatabaseGateway();
    shutdownEvents = <String>[];

    getIt
      ..registerSingleton<IOdbcStreamingSessionCache>(streamingCache)
      ..registerSingleton<IConnectionPool>(connectionPool)
      ..registerSingleton<IDatabaseGateway>(queuedGateway);

    when(() => queuedGateway.disposeGracefully()).thenAnswer((_) async {
      shutdownEvents.add('dispose_sql_queue');
      return const Success(unit);
    });
    when(() => streamingCache.drainCachedSessions()).thenAnswer((_) async {
      shutdownEvents.add('drain_streaming_cache');
      return const Success(unit);
    });
    when(() => connectionPool.closeAll()).thenAnswer((_) async {
      shutdownEvents.add('close_pool');
      return const Success(unit);
    });
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('drains streaming session cache before closing connection pool', () async {
    final sequence = AppShutdownSequence(getIt);

    await sequence.run(
      runEarlyShutdownCoordinator: () async {},
      dispatchAppCloseAgentActions: () async {},
      applyOnAppExitPolicies: () async {},
      shutdownOdbcWorker: () {},
      resetShutdownStateForTesting: () {},
    );

    expect(
      shutdownEvents,
      <String>['dispose_sql_queue', 'drain_streaming_cache', 'close_pool'],
    );
    verifyInOrder([
      () => queuedGateway.disposeGracefully(),
      () => streamingCache.drainCachedSessions(),
      () => connectionPool.closeAll(),
    ]);
  });

  test('runs hub early phase after app-close dispatch and onAppExit policies', () async {
    final sequence = AppShutdownSequence(getIt);

    await sequence.run(
      runEarlyShutdownCoordinator: () async {
        shutdownEvents.add('early_shutdown');
      },
      dispatchAppCloseAgentActions: () async {
        shutdownEvents.add('app_close');
      },
      applyOnAppExitPolicies: () async {
        shutdownEvents.add('on_app_exit');
      },
      shutdownOdbcWorker: () {},
      resetShutdownStateForTesting: () {},
    );

    expect(
      shutdownEvents.take(3),
      <String>['app_close', 'on_app_exit', 'early_shutdown'],
    );
  });

  test('disposes in order: early → action queue → sql queue → drain → pool', () async {
    final actionQueue = ActionExecutionQueue();
    getIt.registerSingleton<ActionExecutionQueue>(actionQueue);

    when(() => queuedGateway.disposeGracefully()).thenAnswer((_) async {
      expect(
        actionQueue.isDisposed,
        isTrue,
        reason: 'action queue must be disposed before SQL queue dispose',
      );
      shutdownEvents.add('dispose_sql_queue');
      return const Success(unit);
    });

    final sequence = AppShutdownSequence(getIt);
    await sequence.run(
      runEarlyShutdownCoordinator: () async {
        shutdownEvents.add('early_shutdown');
      },
      dispatchAppCloseAgentActions: () async {},
      applyOnAppExitPolicies: () async {},
      shutdownOdbcWorker: () {},
      resetShutdownStateForTesting: () {},
    );

    expect(actionQueue.isDisposed, isTrue);
    expect(
      shutdownEvents,
      <String>[
        'early_shutdown',
        'dispose_sql_queue',
        'drain_streaming_cache',
        'close_pool',
      ],
    );
    verifyInOrder([
      () => queuedGateway.disposeGracefully(),
      () => streamingCache.drainCachedSessions(),
      () => connectionPool.closeAll(),
    ]);
  });
}
