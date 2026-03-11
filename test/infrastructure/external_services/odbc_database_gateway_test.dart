import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  group('OdbcDatabaseGateway', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late MockConnectionPool mockConnectionPool;
    late IRetryManager retryManager;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcDatabaseGateway gateway;

    setUp(() {
      mockService = MockOdbcService();
      mockConfigRepository = MockAgentConfigRepository();
      mockConnectionPool = MockConnectionPool();
      retryManager = RetryManager.instance;
      metrics = MetricsCollector.instance..clear();
      mockSettings = MockOdbcConnectionSettings();
      gateway = OdbcDatabaseGateway(
        mockConfigRepository,
        mockService,
        mockConnectionPool,
        retryManager,
        metrics,
        mockSettings,
      );
    });

    test(
      'should fallback to direct connection on invalid pooled connection id',
      () async {
        const pooledConnectionId = '100000';
        const directConnectionId = 'direct-1';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ValidationError(message: 'Invalid connection ID: 100000'),
          );
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: directConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test('should keep success even when pool release fails', () async {
      const pooledConnectionId = 'pool-1';
      const sql = 'SELECT * FROM users';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-2',
        agentId: config.agentId,
        query: sql,
        timestamp: DateTime.now(),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return Failure(Exception('release failed'));
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
    });

    test('should retry with expanded buffer when pooled query buffer is too small', () async {
      const pooledConnectionId = 'pool-buffer';
      const directConnectionId = 'direct-buffer';
      const sql = 'SELECT * FROM very_large_table';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-buffer',
        agentId: config.agentId,
        query: sql,
        timestamp: DateTime.now(),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Failure(
          QueryError(
            message: 'Buffer too small: need 60830894 bytes, got 33554432',
          ),
        );
      });
      when(
        () => mockService.connect(any(), options: any(named: 'options')),
      ).thenAnswer((_) async {
        return Success(
          Connection(
            id: directConnectionId,
            connectionString: connectionString,
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: directConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockService.disconnect(directConnectionId)).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      verify(
        () => mockService.connect(any(), options: any(named: 'options')),
      ).called(1);
      verify(() => mockService.disconnect(directConnectionId)).called(1);
      verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
    });
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
