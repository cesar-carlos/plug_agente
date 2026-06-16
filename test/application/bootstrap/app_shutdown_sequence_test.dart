import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_sequence.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockStreamingSessionCache extends Mock implements IOdbcStreamingSessionCache {}

void main() {
  late GetIt getIt;
  late _MockStreamingSessionCache streamingCache;
  late _MockConnectionPool connectionPool;
  late List<String> shutdownEvents;

  setUp(() {
    getIt = GetIt.asNewInstance();
    streamingCache = _MockStreamingSessionCache();
    connectionPool = _MockConnectionPool();
    shutdownEvents = <String>[];

    getIt
      ..registerSingleton<IOdbcStreamingSessionCache>(streamingCache)
      ..registerSingleton<IConnectionPool>(connectionPool);

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

    expect(shutdownEvents, <String>['drain_streaming_cache', 'close_pool']);
    verifyInOrder([
      () => streamingCache.drainCachedSessions(),
      () => connectionPool.closeAll(),
    ]);
  });
}
