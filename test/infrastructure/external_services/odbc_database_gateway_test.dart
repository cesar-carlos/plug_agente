import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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
      retryManager = RetryManager();
      metrics = MetricsCollector()..clear();
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

    test(
      'should retry with expanded buffer when pooled query buffer is too small',
      () async {
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

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
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
              [3],
              [4],
              [5],
            ],
            rowCount: 3,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

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

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('requires an explicit ORDER BY'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should reject SQL Anywhere pagination without explicit order by terms',
      () async {
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-anywhere-page-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('requires an explicit ORDER BY'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should reject preserve_sql combined with managed pagination in gateway',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-preserve-sql-pagination',
          agentId: config.agentId,
          query: 'SELECT * FROM users ORDER BY id',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'id',
                lookupKey: 'id',
              ),
            ],
          ),
          sqlHandlingMode: SqlHandlingMode.preserve,
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('preserve_sql cannot be combined with managed pagination'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test('should apply PostgreSQL pagination syntax', () async {
      const pooledConnectionId = 'pool-pg';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(
        connectionString,
        driverName: 'PostgreSQL',
        odbcDriverName: 'PostgreSQL Unicode',
      );
      final request = QueryRequest(
        id: 'req-pg',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 1,
          pageSize: 10,
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
        ),
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
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('ORDER BY id ASC'));
      expect(capturedSql, contains('LIMIT 11 OFFSET 0'));
    });

    test(
      'should allow PostgreSQL pagination without explicit order by terms',
      () async {
        const pooledConnectionId = 'pool-pg-no-order';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'PostgreSQL',
          odbcDriverName: 'PostgreSQL Unicode',
        );
        final request = QueryRequest(
          id: 'req-pg-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
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
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final capturedSql =
            verify(
                  () => mockService.executeQuery(
                    captureAny(),
                    connectionId: pooledConnectionId,
                  ),
                ).captured.single
                as String;
        expect(capturedSql, contains('LIMIT 11 OFFSET 0'));
        expect(capturedSql, isNot(contains('ORDER BY')));
      },
    );

    test(
      'should reject SQL that already declares pagination clauses when options pagination is active',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-sql-has-limit',
          agentId: config.agentId,
          query: 'SELECT * FROM users LIMIT 10',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('cannot include LIMIT/OFFSET/FETCH'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should prefer persisted connection string instead of rebuilding one',
      () async {
        const persistedConnectionString =
            'DSN=PersistedConnection;Encrypt=yes;';
        final config = _buildConfig(persistedConnectionString);
        final request = QueryRequest(
          id: 'req-conn-string',
          agentId: config.agentId,
          query: 'SELECT 1',
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
          return const Success('pool-1');
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: 'pool-1',
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['value'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockConnectionPool.release('pool-1')).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockConnectionPool.acquire(persistedConnectionString),
        ).called(1);
      },
    );

    test('should apply keyset cursor pagination syntax', () async {
      const pooledConnectionId = 'pool-cursor';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-cursor',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 2,
          pageSize: 2,
          cursor: 'cursor-1',
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
          lastRowValues: [2],
        ),
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
              [3],
              [4],
              [5],
            ],
            rowCount: 3,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('WHERE (id > 2)'));
      expect(capturedSql, contains('ORDER BY id ASC'));
      expect(capturedSql, contains('FETCH NEXT 3 ROWS ONLY'));
    });

    test('should map multiple result sets and row counts', () async {
      const pooledConnectionId = 'pool-multi';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-multi',
        agentId: config.agentId,
        query:
            'SELECT 1 AS first_value; UPDATE users SET active = 1; SELECT 2 AS second_value;',
        timestamp: DateTime.now(),
        expectMultipleResults: true,
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
        () => mockService.executeQueryMultiFull(
          pooledConnectionId,
          any(),
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResultMulti(
            items: [
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['first_value'],
                  rows: [
                    [1],
                  ],
                  rowCount: 1,
                ),
              ),
              QueryResultMultiItem.rowCount(3),
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['second_value'],
                  rows: [
                    [2],
                  ],
                  rowCount: 1,
                ),
              ),
            ],
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull()!;
      expect(response.data.single['first_value'], 1);
      expect(response.resultSets, hasLength(2));
      expect(response.items, hasLength(3));
      expect(response.items[1].rowCount, 3);
      expect(response.columnMetadata, [
        {'name': 'first_value'},
      ]);
      verify(
        () => mockService.executeQueryMultiFull(
          pooledConnectionId,
          request.query,
        ),
      ).called(1);
    });
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
