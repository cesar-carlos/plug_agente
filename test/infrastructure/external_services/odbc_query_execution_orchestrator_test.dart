import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(const ConnectionAcquireOptions());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<Object?>[]);
  });

  group('OdbcQueryExecutionOrchestrator', () {
    late MockOdbcService mockService;
    late MockConnectionPool mockConnectionPool;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcQueryExecutionOrchestrator orchestrator;

    setUp(() {
      mockService = MockOdbcService();
      mockConnectionPool = MockConnectionPool();
      metrics = MetricsCollector()..clear();
      mockSettings = MockOdbcConnectionSettings();

      final connectionManager = OdbcGatewayConnectionManager(
        service: mockService,
        connectionPool: mockConnectionPool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
            mockSettings.poolSize,
          ),
          acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
          metricsCollector: metrics,
        ),
        metrics: metrics,
        directConnectionMaxProvider: () => ConnectionConstants.directOdbcConnectionConcurrency(
          mockSettings.poolSize,
        ),
      );
      final statementExecutor = OdbcStatementExecutor(
        service: mockService,
        metrics: metrics,
        markConnectionForDiscard: connectionManager.markConnectionForDiscard,
      );
      final queryRunner = OdbcQueryRunner(
        queries: mockService,
        metrics: metrics,
        statementExecutor: statementExecutor,
        resultEncodingExecutor: OdbcResultEncodingExecutor(mockService),
        markConnectionForDiscard: connectionManager.markConnectionForDiscard,
      );
      orchestrator = OdbcQueryExecutionOrchestrator(
        connectionManager: connectionManager,
        queryRunner: queryRunner,
        optionsResolver: OdbcConnectionOptionsResolver(mockSettings),
        nativeCompatiblePolicy: NativeCompatibleAcquirePolicy(),
        metrics: metrics,
      );

      when(() => mockConnectionPool.discard(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(
        () => mockConnectionPool.getActiveCount(
          connectionString: any(named: 'connectionString'),
        ),
      ).thenAnswer((_) async {
        return const Success(0);
      });
      when(
        () => mockService.prepare(
          any(),
          any(),
          timeoutMs: any(named: 'timeoutMs'),
        ),
      ).thenAnswer((_) async => const Success(9001));
      when(
        () => mockService.executePreparedParamValuesFromObjects(
          any(),
          any(),
          any(),
          any(),
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
      when(() => mockService.closeStatement(any(), any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockService.cancelStatement(any(), any())).thenAnswer((_) async {
        return const Success(unit);
      });
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

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
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
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          request,
          connectionString,
          _buildDatabaseConfig(config),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test(
      'should retry pooled query with expanded buffer after buffer-too-small error',
      () async {
        const firstPooledId = 'pool-buffer-1';
        const retryPooledId = 'pool-buffer-2';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-buffer-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );
        final capturedAcquireBuffers = <int>[];
        var acquireCount = 0;

        when(
          () => mockConnectionPool.acquire(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          acquireCount++;
          final options = invocation.namedArguments[#options] as ConnectionAcquireOptions?;
          if (acquireCount == 1) {
            return const Success(firstPooledId);
          }
          if (options == null) {
            return Failure(domain.ConnectionFailure('unexpected pooled acquire without options'));
          }
          capturedAcquireBuffers.add(options.maxResultBufferBytes ?? 0);
          return const Success(retryPooledId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          final connectionId = invocation.namedArguments[#connectionId] as String;
          if (connectionId == firstPooledId) {
            return const Failure(
              ValidationError(message: 'buffer too small: need 67108864 bytes'),
            );
          }
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
        when(() => mockConnectionPool.release(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          request,
          connectionString,
          _buildDatabaseConfig(config),
        );

        expect(result.isSuccess(), isTrue);
        expect(acquireCount, 2);
        expect(capturedAcquireBuffers, hasLength(1));
        expect(capturedAcquireBuffers.single, greaterThan(32 * 1024 * 1024));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
      },
    );

    test('should apply SQL Server pagination and expose hasNextPage', () async {
      const pooledConnectionId = 'pool-page';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-page',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 2,
          pageSize: 2,
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
        ),
      );

      when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
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
              [3],
              [4],
              [5],
            ],
            rowCount: 3,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
        return const Success(unit);
      });

      final result = await orchestrator.execute(
        request,
        connectionString,
        _buildDatabaseConfig(config),
      );

      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull()!;
      expect(response.data, hasLength(2));
      expect(response.pagination, isNotNull);
      expect(response.pagination!.page, 2);
      expect(response.pagination!.hasNextPage, isTrue);
      expect(response.pagination!.nextCursor, isNotNull);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('OFFSET 2 ROWS'));
      expect(capturedSql, contains('FETCH NEXT 3 ROWS ONLY'));
      expect(capturedSql, contains('ORDER BY id ASC'));
    });

    test(
      'should reject SQL Server pagination without explicit order by terms',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-page-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        final result = await orchestrator.execute(
          request,
          connectionString,
          _buildDatabaseConfig(config),
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('requires an explicit ORDER BY'),
          );
        } else {
          fail('expected ValidationFailure, got $failure');
        }
      },
    );

    test(
      'should fallback to direct connection when pooled multi-result is vacuous',
      () async {
        const pooledConnectionId = 'pool-multi-empty';
        const directConnectionId = 'direct-multi';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const sql = 'SELECT 1 AS a; SELECT 2 AS b;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-multi-fallback',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
          expectMultipleResults: true,
        );

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.streamQueryMulti(
            pooledConnectionId,
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSize: any(named: 'chunkSize'),
          ),
        ).thenAnswer((_) => const Stream<Result<QueryResultMultiItem>>.empty());
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
          () => mockService.streamQueryMulti(
            directConnectionId,
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSize: any(named: 'chunkSize'),
          ),
        ).thenAnswer((_) {
          return Stream<Result<QueryResultMultiItem>>.fromIterable(const [
            Success(
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['a'],
                  rows: [
                    [1],
                  ],
                  rowCount: 1,
                ),
              ),
            ),
            Success(
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['b'],
                  rows: [
                    [2],
                  ],
                  rowCount: 1,
                ),
              ),
            ),
          ]);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          request,
          connectionString,
          _buildDatabaseConfig(config),
        );

        expect(result.isSuccess(), isTrue);
        final response = result.getOrNull()!;
        expect(response.resultSets, hasLength(2));
        expect(response.data.single['a'], 1);
        verify(
          () => mockService.streamQueryMulti(pooledConnectionId, sql, fetchSize: any(named: 'fetchSize'), chunkSize: any(named: 'chunkSize')),
        ).called(1);
        verify(
          () => mockService.streamQueryMulti(directConnectionId, sql, fetchSize: any(named: 'fetchSize'), chunkSize: any(named: 'chunkSize')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        expect(metrics.multiResultPoolVacuousFallbackCount, 1);
        expect(metrics.multiResultDirectStillVacuousCount, 0);
      },
    );

    test(
      'should reuse adaptive buffer hint through pooled acquire on recurring query',
      () async {
        const firstPooledId = 'pool-buffer-1';
        const retryPooledId = 'pool-buffer-2';
        const hintedPooledId = 'pool-buffer-3';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request1 = QueryRequest(
          id: 'req-buffer-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );
        final request2 = QueryRequest(
          id: 'req-buffer-2',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );
        final capturedAcquireBuffers = <int>[];
        var acquireCount = 0;

        when(
          () => mockConnectionPool.acquire(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          acquireCount++;
          final options = invocation.namedArguments[#options] as ConnectionAcquireOptions?;
          if (acquireCount == 1) {
            return const Success(firstPooledId);
          }
          if (options == null) {
            return Failure(domain.ConnectionFailure('unexpected pooled acquire without options'));
          }
          capturedAcquireBuffers.add(options.maxResultBufferBytes ?? 0);
          return Success(
            acquireCount == 2 ? retryPooledId : hintedPooledId,
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          final connectionId = invocation.namedArguments[#connectionId] as String;
          if (connectionId == firstPooledId) {
            return const Failure(
              ValidationError(message: 'buffer too small: need 67108864 bytes'),
            );
          }
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
        when(() => mockConnectionPool.release(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final first = await orchestrator.execute(
          request1,
          connectionString,
          _buildDatabaseConfig(config),
        );
        final second = await orchestrator.execute(
          request2,
          connectionString,
          _buildDatabaseConfig(config),
        );

        expect(first.isSuccess(), isTrue);
        expect(second.isSuccess(), isTrue);
        expect(acquireCount, 3);
        expect(capturedAcquireBuffers, hasLength(2));
        expect(capturedAcquireBuffers[0], greaterThan(32 * 1024 * 1024));
        expect(capturedAcquireBuffers[1], equals(capturedAcquireBuffers[0]));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
      },
    );
  });
}

Config _buildConfig(
  String connectionString, {
  String driverName = 'SQL Server',
  String odbcDriverName = 'ODBC Driver 17 for SQL Server',
}) {
  final now = DateTime.now();
  return Config(
    id: 'cfg-1',
    driverName: driverName,
    odbcDriverName: odbcDriverName,
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

DatabaseConfig _buildDatabaseConfig(
  Config config, {
  DatabaseType databaseType = DatabaseType.sqlServer,
}) {
  return DatabaseConfig(
    driverName: config.odbcDriverName,
    username: config.username,
    password: config.password ?? '',
    database: config.databaseName,
    server: config.host,
    port: config.port,
    databaseType: databaseType,
  );
}
