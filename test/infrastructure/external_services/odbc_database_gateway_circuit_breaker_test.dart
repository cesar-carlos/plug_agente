import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_query_config_source.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(const ConnectionAcquireOptions());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<Object?>[]);
  });

  group('OdbcDatabaseGateway circuit breaker', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late MockConnectionPool mockConnectionPool;
    late OdbcDatabaseGateway gateway;

    setUp(() {
      dotenv.clean();
      dotenv.loadFromString(
        envString:
            'CIRCUIT_BREAKER_FAILURE_THRESHOLD=1\n'
            'CIRCUIT_BREAKER_RESET_SEC=30',
      );

      mockService = MockOdbcService();
      mockConfigRepository = MockAgentConfigRepository();
      mockConnectionPool = MockConnectionPool();
      gateway = OdbcDatabaseGateway(
        AgentConfigQueryConfigSource(mockConfigRepository),
        mockService,
        mockConnectionPool,
        RetryManager(),
        MetricsCollector()..clear(),
        MockOdbcConnectionSettings(),
      );

      when(() => mockConnectionPool.discard(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(
        () => mockConnectionPool.getActiveCount(
          connectionString: any(named: 'connectionString'),
        ),
      ).thenAnswer((_) async => const Success(0));
      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
    });

    tearDown(dotenv.clean);

    test(
      'opens circuit after threshold and fast-fails executeQuery without calling pool',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-cb-open',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer(
          (_) async => Success(config),
        );
        var poolAcquireCount = 0;
        when(
          () => mockConnectionPool.acquire(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async {
            poolAcquireCount++;
            return Failure(
              domain.ConnectionFailure.withContext(
                message: 'Could not reach the database server',
                context: {
                  'connectionFailed': true,
                  'reason': OdbcContextConstants.serverUnreachableReason,
                },
              ),
            );
          },
        );

        final firstResult = await gateway.executeQuery(request);
        expect(firstResult.isError(), isTrue);
        final acquireCountAfterFirstQuery = poolAcquireCount;
        expect(acquireCountAfterFirstQuery, greaterThan(0));

        final secondResult = await gateway.executeQuery(request);
        expect(secondResult.isError(), isTrue);
        final failure = secondResult.exceptionOrNull()! as domain.ConnectionFailure;
        expect(
          failure.context['reason'],
          equals(OdbcContextConstants.circuitBreakerOpenReason),
        );
        expect(poolAcquireCount, equals(acquireCountAfterFirstQuery));
      },
    );

    test(
      'does not open circuit when ODBC maps authentication failure',
      () async {
        const pooledConnectionId = 'pool-auth-1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-cb-auth',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer(
          (_) async => Success(config),
        );
        when(
          () => mockConnectionPool.acquire(any(), options: any(named: 'options')),
        ).thenAnswer((_) async => const Success(pooledConnectionId));
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer(
          (_) async => const Failure(
            ValidationError(message: 'Invalid connection ID'),
          ),
        );
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => const Failure(
            ConnectionError(
              message: 'Login failed for user',
              sqlState: '28000',
            ),
          ),
        );
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final firstResult = await gateway.executeQuery(request);
        expect(firstResult.isError(), isTrue);
        expect(firstResult.exceptionOrNull(), isA<domain.ConfigurationFailure>());

        final secondResult = await gateway.executeQuery(request);
        expect(secondResult.isError(), isTrue);
        expect(
          secondResult.exceptionOrNull(),
          isA<domain.ConfigurationFailure>(),
        );

        verify(
          () => mockConnectionPool.acquire(any(), options: any(named: 'options')),
        ).called(2);
      },
    );
  });
}

Config _buildConfig(String connectionString) {
  final now = DateTime.now();
  return Config(
    id: 'cfg-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: connectionString,
    username: 'sa',
    databaseName: 'master',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
    agentId: 'agent-1',
  );
}
