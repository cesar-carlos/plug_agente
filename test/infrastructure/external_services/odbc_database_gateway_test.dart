import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
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

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

class MockNativeCompatibleConnectionPool extends Mock
    implements IConnectionPool, INativeCompatibleConnectionPoolAcquire {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(Duration.zero);
  });

  group('OdbcDatabaseGateway', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late MockConnectionPool mockConnectionPool;
    late IRetryManager retryManager;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcDatabaseGateway gateway;

    setUp(() {
      dotenv.clean();
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
        () => mockService.prepareNamed(
          any(),
          any(),
          timeoutMs: any(named: 'timeoutMs'),
        ),
      ).thenAnswer((_) async => const Success(9002));
      when(
        () => mockService.executePrepared(
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
      when(
        () => mockService.executePreparedNamed(
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
      when(() => mockService.executeAsyncStart(any(), any())).thenAnswer((_) async {
        return const Failure(
          UnsupportedFeatureError(message: 'async execution unsupported'),
        );
      });
      when(() => mockService.asyncPoll(any())).thenAnswer((_) async {
        return const Success(1);
      });
      when(
        () => mockService.asyncGetResult(
          any(),
          maxBufferBytes: any(named: 'maxBufferBytes'),
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(columns: [], rows: [], rowCount: 0),
        );
      });
      when(() => mockService.asyncCancel(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockService.asyncFree(any())).thenAnswer((_) async {
        return const Success(unit);
      });
    });

    tearDown(dotenv.clean);

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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
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
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test(
      'should record structured connect timeout on direct fallback from upstream invalid connection id',
      () async {
        const pooledConnectionId = 'pool-invalid-upstream';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-timeout-fallback-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
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
            ValidationError(message: 'Invalid connection ID'),
          );
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return const Failure(
            ConnectionError(
              message: 'Login handshake stalled',
              sqlState: 'HYT00',
            ),
          );
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
        expect(metrics.connectTimeoutCount, 1);
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test(
      'should fallback to direct connection on structured invalid pooled connection id',
      () async {
        const pooledConnectionId = 'pool-invalid-native';
        const directConnectionId = 'direct-native-1';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-invalid-native-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
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
            ConnectionError(
              message: 'stale handle from worker',
              nativeCode: 100000,
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
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(() => mockService.connect(any(), options: any(named: 'options'))).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test(
      'should skip pool recycle when another lease for the same DSN is still active',
      () async {
        const pooledConnectionId = 'pool-invalid-shared';
        const directConnectionId = 'direct-shared-1';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-invalid-shared-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockConnectionPool.getActiveCount(
            connectionString: connectionString,
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ConnectionError(
              message: 'stale handle from worker',
              nativeCode: 100000,
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

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verifyNever(() => mockConnectionPool.recycle(connectionString));
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

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockConnectionPool.acquire(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          acquireCount++;
          final options = invocation.namedArguments[#options] as ConnectionOptions?;
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

        final first = await gateway.executeQuery(request1);
        final second = await gateway.executeQuery(request2);

        expect(first.isSuccess(), isTrue);
        expect(second.isSuccess(), isTrue);
        expect(acquireCount, 3);
        expect(capturedAcquireBuffers, hasLength(2));
        expect(capturedAcquireBuffers[0], greaterThan(32 * 1024 * 1024));
        expect(capturedAcquireBuffers[1], equals(capturedAcquireBuffers[0]));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
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
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
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

    test('should allow executeQueryNamed with more than five named parameters', () async {
      const pooledConnectionId = 'pool-many-params';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      const sql = '''
SELECT * FROM users
WHERE a = :a AND b = :b AND c = :c AND d = :d AND e = :e AND f = :f
''';
      const parameters = {
        'a': 1,
        'b': 2,
        'c': 3,
        'd': 4,
        'e': 5,
        'f': 6,
      };
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-many-params',
        agentId: config.agentId,
        query: sql,
        parameters: parameters,
        timestamp: DateTime.now(),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQueryNamed(
          pooledConnectionId,
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
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      verify(
        () => mockService.executeQueryNamed(
          pooledConnectionId,
          sql,
          parameters,
        ),
      ).called(1);
    });

    test('should allow repeated named placeholders with colon and at-sign syntax', () async {
      const pooledConnectionId = 'pool-repeated-named';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      const sql = '''
SELECT * FROM users
WHERE id = :id OR parent_id = :id OR label = @label OR alias = @label
''';
      const parameters = {
        'id': 42,
        'label': 'active',
      };
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-repeated-named',
        agentId: config.agentId,
        query: sql,
        parameters: parameters,
        timestamp: DateTime.now(),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQueryNamed(
          pooledConnectionId,
          any(),
          any(),
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [42],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      verify(
        () => mockService.executeQueryNamed(
          pooledConnectionId,
          sql,
          parameters,
        ),
      ).called(1);
    });

    test(
      'should retry with expanded buffer when pooled query buffer is too small',
      () async {
        const pooledConnectionId = 'pool-buffer-1';
        const retriedPooledId = 'pool-buffer-2';
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        final capturedRetryBuffers = <int>[];
        var acquireCount = 0;
        when(
          () => mockConnectionPool.acquire(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          acquireCount++;
          final options = invocation.namedArguments[#options] as ConnectionOptions?;
          if (acquireCount == 1) {
            return const Success(pooledConnectionId);
          }
          if (options == null) {
            return Failure(domain.ConnectionFailure('unexpected pooled acquire without options'));
          }
          capturedRetryBuffers.add(options.maxResultBufferBytes ?? 0);
          return const Success(retriedPooledId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          final connectionId = invocation.namedArguments[#connectionId] as String;
          if (connectionId == pooledConnectionId) {
            return const Failure(
              QueryError(
                message: 'Buffer too small: need 60830894 bytes, got 33554432',
              ),
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

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        expect(capturedRetryBuffers, hasLength(1));
        expect(capturedRetryBuffers.single, greaterThan(32 * 1024 * 1024));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.release(retriedPooledId)).called(1);
      },
    );

    test(
      'should retry with expanded buffer when pooled query exposes mapped buffer-too-small failure',
      () async {
        const pooledConnectionId = 'pool-buffer-mapped-1';
        const retriedPooledId = 'pool-buffer-mapped-2';
        const sql = 'SELECT * FROM very_large_table';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-buffer-mapped',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        final capturedRetryBuffers = <int>[];
        var acquireCount = 0;
        when(
          () => mockConnectionPool.acquire(
            any(),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          acquireCount++;
          final options = invocation.namedArguments[#options] as ConnectionOptions?;
          if (acquireCount == 1) {
            return const Success(pooledConnectionId);
          }
          if (options == null) {
            return Failure(domain.ConnectionFailure('unexpected pooled acquire without options'));
          }
          capturedRetryBuffers.add(options.maxResultBufferBytes ?? 0);
          return const Success(retriedPooledId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          final connectionId = invocation.namedArguments[#connectionId] as String;
          if (connectionId == pooledConnectionId) {
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Result buffer exceeded',
                context: {
                  'reason': 'buffer_too_small',
                  'odbc_message': 'Buffer too small: need 60830894 bytes, got 33554432',
                },
              ),
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

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        expect(capturedRetryBuffers, hasLength(1));
        expect(capturedRetryBuffers.single, greaterThan(32 * 1024 * 1024));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.release(retriedPooledId)).called(1);
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
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
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
      'should apply SQL Anywhere offset pagination with TOP START AT syntax',
      () async {
        const pooledConnectionId = 'pool-sa-page';
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-sa-page',
          agentId: config.agentId,
          query: 'SELECT * FROM produto ORDER BY CodProduto',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 2,
            pageSize: 2,
            queryHash: 'query-hash',
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'CodProduto',
                lookupKey: 'CodProduto',
              ),
            ],
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
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
              columns: ['CodProduto'],
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
        expect(capturedSql, contains('TOP 3 START AT 3'));
        expect(capturedSql, isNot(contains('OFFSET')));
        expect(capturedSql, isNot(contains('FETCH NEXT')));
        expect(capturedSql, contains('ORDER BY CodProduto ASC'));
      },
    );

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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
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
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
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
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
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
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
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
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
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
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
      },
    );

    test(
      'should prefer persisted connection string instead of rebuilding one',
      () async {
        const persistedConnectionString = 'DSN=PersistedConnection;Encrypt=yes;';
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
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
          () => mockConnectionPool.acquire(
            persistedConnectionString,
            options: any(named: 'options'),
          ),
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
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
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

    test(
      'should apply SQL Anywhere keyset cursor pagination with TOP syntax',
      () async {
        const pooledConnectionId = 'pool-sa-cursor';
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-sa-cursor',
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
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
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
        expect(capturedSql, contains('TOP 3'));
        expect(capturedSql, contains('WHERE (id > 2)'));
        expect(capturedSql, contains('ORDER BY id ASC'));
        expect(capturedSql, isNot(contains('OFFSET')));
        expect(capturedSql, isNot(contains('FETCH NEXT')));
      },
    );

    test('should map multiple result sets and row counts', () async {
      const pooledConnectionId = 'pool-multi';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-multi',
        agentId: config.agentId,
        query: 'SELECT 1 AS first_value; UPDATE users SET active = 1; SELECT 2 AS second_value;',
        timestamp: DateTime.now(),
        expectMultipleResults: true,
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
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

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQueryMultiFull(
            pooledConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
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
          () => mockService.executeQueryMultiFull(
            directConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResultMulti(
              items: [
                QueryResultMultiItem.resultSet(
                  QueryResult(
                    columns: ['a'],
                    rows: [
                      [1],
                    ],
                    rowCount: 1,
                  ),
                ),
                QueryResultMultiItem.resultSet(
                  QueryResult(
                    columns: ['b'],
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
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final response = result.getOrNull()!;
        expect(response.resultSets, hasLength(2));
        expect(response.data.single['a'], 1);
        verify(
          () => mockService.executeQueryMultiFull(pooledConnectionId, sql),
        ).called(1);
        verify(
          () => mockService.executeQueryMultiFull(directConnectionId, sql),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        expect(metrics.multiResultPoolVacuousFallbackCount, 1);
        expect(metrics.multiResultDirectStillVacuousCount, 0);
      },
    );

    test(
      'should record direct-still-vacuous when pool and direct multi are empty',
      () async {
        const pooledConnectionId = 'pool-multi-empty-twice';
        const directConnectionId = 'direct-multi-empty';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const sql = 'SELECT 1 AS a; SELECT 2 AS b;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-multi-empty-both',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
          expectMultipleResults: true,
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQueryMultiFull(
            pooledConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
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
          () => mockService.executeQueryMultiFull(
            directConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final response = result.getOrNull()!;
        expect(response.resultSets, isEmpty);
        expect(metrics.multiResultPoolVacuousFallbackCount, 1);
        expect(metrics.multiResultDirectStillVacuousCount, 1);
      },
    );

    test(
      'should use direct ODBC connection for transactional executeBatch',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-tx-1';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: ownedId,
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
        when(() => mockService.commitTransaction(ownedId, 1)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(
            transaction: true,
            timeoutMs: 1200,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: SavepointDialect.auto,
            accessMode: TransactionAccessMode.readWrite,
            lockTimeout: const Duration(milliseconds: 1200),
          ),
        ).called(1);
        verify(() => mockService.disconnect(ownedId)).called(1);
        expect(metrics.transactionalBatchDirectPathCount, 1);
      },
    );

    test(
      'should retry transactional batch when transaction start fails with structured invalid connection id',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const firstOwnedId = 'owned-retry-1';
        const secondOwnedId = 'owned-retry-2';
        final config = _buildConfig(connectionString);
        var connectCount = 0;

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          connectCount++;
          final connectionId = connectCount == 1 ? firstOwnedId : secondOwnedId;
          return Success(
            Connection(
              id: connectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            firstOwnedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ConnectionError(
              message: 'stale transaction handle',
              nativeCode: 100000,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            secondOwnedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: secondOwnedId,
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
        when(() => mockService.commitTransaction(secondOwnedId, 1)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(firstOwnedId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(secondOwnedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(
            transaction: true,
            timeoutMs: 1200,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
        verify(
          () => mockService.beginTransaction(
            firstOwnedId,
            savepointDialect: SavepointDialect.auto,
            accessMode: TransactionAccessMode.readWrite,
            lockTimeout: const Duration(milliseconds: 1200),
          ),
        ).called(1);
        verify(
          () => mockService.beginTransaction(
            secondOwnedId,
            savepointDialect: SavepointDialect.auto,
            accessMode: TransactionAccessMode.readWrite,
            lockTimeout: const Duration(milliseconds: 1200),
          ),
        ).called(1);
        verify(() => mockService.disconnect(firstOwnedId)).called(1);
        verify(() => mockService.disconnect(secondOwnedId)).called(1);
        verifyNever(() => mockConnectionPool.recycle(any()));
        expect(metrics.transactionalBatchDirectPathCount, 1);
      },
    );

    test(
      'should reuse prepared statements for repeated transactional batch commands',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-prepared-1';
        const stmtId = 77;
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.prepareNamed(
            ownedId,
            'SELECT * FROM users WHERE id = :id',
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).thenAnswer((_) async => const Success(stmtId));
        when(
          () => mockService.executePreparedNamed(
            ownedId,
            stmtId,
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
        when(() => mockService.commitTransaction(ownedId, 1)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.closeStatement(ownedId, stmtId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(
              sql: 'SELECT * FROM users WHERE id = :id',
              params: {'id': 1},
            ),
            SqlCommand(
              sql: 'SELECT * FROM users WHERE id = :id',
              params: {'id': 2},
            ),
          ],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => mockService.executeQuery(
            any(),
            connectionId: ownedId,
          ),
        );
        verify(
          () => mockService.prepareNamed(
            ownedId,
            'SELECT * FROM users WHERE id = :id',
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).called(1);
        verify(
          () => mockService.executePreparedNamed(
            ownedId,
            stmtId,
            any(),
            any(),
          ),
        ).called(2);
        verify(() => mockService.closeStatement(ownedId, stmtId)).called(1);
      },
    );

    test(
      'should recover non-transactional batch command after invalid pooled connection id',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const firstConnectionId = 'pool-batch-1';
        const secondConnectionId = 'pool-batch-2';
        final config = _buildConfig(connectionString);
        var acquireCount = 0;

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
          acquireCount++;
          return Success(acquireCount == 1 ? firstConnectionId : secondConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: firstConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ConnectionError(
              message: 'Invalid connection ID: stale handle',
              nativeCode: 100000,
            ),
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: secondConnectionId,
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
        when(() => mockConnectionPool.discard(firstConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(secondConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.recycle(connectionString)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(timeoutMs: 1200),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        final items = result.getOrNull()!;
        expect(items, hasLength(1));
        expect(items.single.ok, isTrue);
        verify(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).called(2);
        verify(() => mockConnectionPool.discard(firstConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(connectionString)).called(1);
        verify(() => mockConnectionPool.release(secondConnectionId)).called(1);
        verify(
          () => mockService.executeQuery(
            'SELECT 1',
            connectionId: firstConnectionId,
          ),
        ).called(1);
        verify(
          () => mockService.executeQuery(
            'SELECT 1',
            connectionId: secondConnectionId,
          ),
        ).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
      },
    );

    test(
      'should avoid prepared statement churn for timed non-transactional batch commands',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const pooledConnectionId = 'pool-batch-direct-timeout-1';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            'SELECT 1',
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
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(timeoutMs: 1200),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.executeQuery(
            'SELECT 1',
            connectionId: pooledConnectionId,
          ),
        ).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
        verifyNever(
          () => mockService.executePrepared(
            any(),
            any(),
            any(),
            any(),
          ),
        );
      },
    );

    test(
      'should execute read-only batch in parallel when opt-in parallelism is provided',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        var acquireCount = 0;
        var activeExecutions = 0;
        var peakExecutions = 0;

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
          acquireCount++;
          return Success('parallel-$acquireCount');
        });
        when(() => mockConnectionPool.release(any())).thenAnswer((_) async {
          return const Success(unit);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          activeExecutions++;
          if (activeExecutions > peakExecutions) {
            peakExecutions = activeExecutions;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          activeExecutions--;
          final sql = invocation.positionalArguments.first as String;
          return Success(
            QueryResult(
              columns: const ['sql'],
              rows: [
                [sql],
              ],
              rowCount: 1,
            ),
          );
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
            SqlCommand(sql: 'SELECT 3'),
          ],
          options: const SqlExecutionOptions(
            timeoutMs: 1200,
            maxParallelReadOnlyBatchItems: 4,
          ),
        );

        expect(result.isSuccess(), isTrue);
        expect(peakExecutions, 2);
        expect(metrics.readOnlyBatchParallelCount, 1);
        expect(metrics.readOnlyBatchParallelCappedCount, 1);
        final items = result.getOrNull()!;
        expect(items.map((item) => item.rows?.single['sql']), ['SELECT 1', 'SELECT 2', 'SELECT 3']);
        verify(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).called(3);
        verify(() => mockConnectionPool.release(any())).called(3);
      },
    );

    test(
      'should cap read-only batch parallelism globally across concurrent batches',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        var acquireCount = 0;
        var activeExecutions = 0;
        var peakExecutions = 0;

        when(() => mockService.initialize()).thenAnswer((_) async => const Success(unit));
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(config));
        when(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
          acquireCount++;
          return Success('global-parallel-$acquireCount');
        });
        when(() => mockConnectionPool.release(any())).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          activeExecutions++;
          peakExecutions = peakExecutions < activeExecutions ? activeExecutions : peakExecutions;
          await Future<void>.delayed(const Duration(milliseconds: 25));
          activeExecutions--;
          final sql = invocation.positionalArguments.first as String;
          return Success(
            QueryResult(
              columns: const ['sql'],
              rows: [
                [sql],
              ],
              rowCount: 1,
            ),
          );
        });

        final batchA = gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
            SqlCommand(sql: 'SELECT 3'),
            SqlCommand(sql: 'SELECT 4'),
          ],
          options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 4),
        );
        final batchB = gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(sql: 'SELECT 5'),
            SqlCommand(sql: 'SELECT 6'),
            SqlCommand(sql: 'SELECT 7'),
            SqlCommand(sql: 'SELECT 8'),
          ],
          options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 4),
        );

        final results = await Future.wait([batchA, batchB]);

        expect(results.every((result) => result.isSuccess()), isTrue);
        expect(peakExecutions, 2);
        expect(metrics.readOnlyBatchParallelCount, 2);
        expect(metrics.readOnlyBatchParallelCappedCount, 2);
        expect(metrics.getSnapshot()['read_only_batch_parallel_wait_sample_count'], 8);
      },
    );

    test(
      'should use native-compatible acquire for safe simple probe queries',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        await featureFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
        final nativePool = MockNativeCompatibleConnectionPool();
        final nativeGateway = OdbcDatabaseGateway(
          mockConfigRepository,
          mockService,
          nativePool,
          retryManager,
          metrics,
          mockSettings,
          featureFlags: featureFlags,
        );
        final request = QueryRequest(
          id: 'req-native-probe',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async => const Success(unit));
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(config));
        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((_) async => const Success('native-1'));
        when(() => nativePool.release('native-1')).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.executeQuery(
            'SELECT 1',
            connectionId: 'native-1',
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: ['value'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );

        final result = await nativeGateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).called(1);
        verifyNever(() => nativePool.acquire(connectionString, options: any(named: 'options')));
      },
    );

    test(
      'should use native-compatible acquire for exact allowlisted small SQL',
      () async {
        dotenv.loadFromString(envString: 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST=select id from users');
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        await featureFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
        final nativePool = MockNativeCompatibleConnectionPool();
        final nativeGateway = OdbcDatabaseGateway(
          mockConfigRepository,
          mockService,
          nativePool,
          retryManager,
          metrics,
          mockSettings,
          featureFlags: featureFlags,
        );
        final request = QueryRequest(
          id: 'req-native-allowlist',
          agentId: config.agentId,
          query: 'SELECT id FROM users',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async => const Success(unit));
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(config));
        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((_) async => const Success('native-allowlist-1'));
        when(() => nativePool.release('native-allowlist-1')).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.executeQuery(
            'SELECT id FROM users',
            connectionId: 'native-allowlist-1',
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );

        final result = await nativeGateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).called(1);
        verifyNever(() => nativePool.acquire(connectionString, options: any(named: 'options')));
      },
    );

    test(
      'should reparse native-compatible SQL allowlist when env value changes inside cache ttl',
      () async {
        dotenv.loadFromString(envString: 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST=select id from users');
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        await featureFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
        final nativePool = MockNativeCompatibleConnectionPool();
        final nativeGateway = OdbcDatabaseGateway(
          mockConfigRepository,
          mockService,
          nativePool,
          retryManager,
          metrics,
          mockSettings,
          featureFlags: featureFlags,
        );

        when(() => mockService.initialize()).thenAnswer((_) async => const Success(unit));
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(config));
        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((invocation) async {
          return Success('native-cache-${DateTime.now().microsecondsSinceEpoch}');
        });
        when(() => nativePool.release(any())).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );

        final first = await nativeGateway.executeQuery(
          QueryRequest(
            id: 'req-native-cache-1',
            agentId: config.agentId,
            query: 'SELECT id FROM users',
            timestamp: DateTime.now(),
          ),
        );
        dotenv.loadFromString(envString: 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST=select id from departments');
        final second = await nativeGateway.executeQuery(
          QueryRequest(
            id: 'req-native-cache-2',
            agentId: config.agentId,
            query: 'SELECT id FROM departments',
            timestamp: DateTime.now(),
          ),
        );

        expect(first.isSuccess(), isTrue);
        expect(second.isSuccess(), isTrue);
        verify(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).called(2);
      },
    );

    test(
      'should avoid native-compatible acquire for wildcard limited selects',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        await featureFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
        final nativePool = MockNativeCompatibleConnectionPool();
        final nativeGateway = OdbcDatabaseGateway(
          mockConfigRepository,
          mockService,
          nativePool,
          retryManager,
          metrics,
          mockSettings,
          featureFlags: featureFlags,
        );
        final request = QueryRequest(
          id: 'req-native-wide',
          agentId: config.agentId,
          query: 'SELECT TOP 10 * FROM users',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async => const Success(unit));
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(config));
        when(
          () => nativePool.acquire(
            connectionString,
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => const Success('lease-1'));
        when(() => nativePool.release('lease-1')).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.executeQuery(
            'SELECT TOP 10 * FROM users',
            connectionId: 'lease-1',
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );

        final result = await nativeGateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        );
        verify(() => nativePool.acquire(connectionString, options: any(named: 'options'))).called(1);
      },
    );

    test(
      'should keep transactional batch execution with more than five named parameters',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-many-params-1';
        const stmtId = 79;
        const sql = '''
SELECT * FROM users
WHERE a = :a AND b = :b AND c = :c AND d = :d AND e = :e AND f = :f
''';
        const parameters = {
          'a': 1,
          'b': 2,
          'c': 3,
          'd': 4,
          'e': 5,
          'f': 6,
        };
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.prepareNamed(
            ownedId,
            sql,
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).thenAnswer((_) async => const Success(stmtId));
        when(
          () => mockService.executePreparedNamed(
            ownedId,
            stmtId,
            parameters,
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
        when(() => mockService.commitTransaction(ownedId, 1)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.closeStatement(ownedId, stmtId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(
              sql: sql,
              params: parameters,
            ),
          ],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.prepareNamed(
            ownedId,
            sql,
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).called(1);
        verify(
          () => mockService.executePreparedNamed(
            ownedId,
            stmtId,
            parameters,
            any(),
          ),
        ).called(1);
      },
    );

    test(
      'should cancel prepared statement when transactional batch item times out',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-prepared-timeout-1';
        const stmtId = 78;
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(1);
        });
        when(
          () => mockService.prepareNamed(
            ownedId,
            'SELECT * FROM users WHERE id = :id',
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).thenAnswer((_) async => const Success(stmtId));
        when(
          () => mockService.executePreparedNamed(
            ownedId,
            stmtId,
            any(),
            any(),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
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
        when(() => mockService.cancelStatement(ownedId, stmtId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.rollbackTransaction(ownedId, 1)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.closeStatement(ownedId, stmtId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [
            SqlCommand(
              sql: 'SELECT * FROM users WHERE id = :id',
              params: {'id': 1},
            ),
            SqlCommand(
              sql: 'SELECT * FROM users WHERE id = :id',
              params: {'id': 2},
            ),
          ],
          options: const SqlExecutionOptions(
            transaction: true,
            timeoutMs: 20,
          ),
        );

        expect(result.isError(), isTrue);
        verify(() => mockService.cancelStatement(ownedId, stmtId)).called(1);
        verify(() => mockService.rollbackTransaction(ownedId, 1)).called(1);
        verify(() => mockService.closeStatement(ownedId, stmtId)).called(1);
        expect(metrics.timeoutCancelSuccessCount, 1);
      },
    );

    test(
      'should rollback transactional batch when execution throws unexpectedly',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-throw-1';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async {
          return const Success(99);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: ownedId,
          ),
        ).thenThrow(StateError('driver panic'));
        when(() => mockService.rollbackTransaction(ownedId, 99)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        verify(() => mockService.rollbackTransaction(ownedId, 99)).called(1);
        verify(() => mockService.disconnect(ownedId)).called(1);
        expect(metrics.transactionRollbackAttemptCount, 1);
      },
    );

    test(
      'should use native async request lifecycle for timed non-query without parameters',
      () async {
        const pooledConnectionId = 'pool-async-non-query-1';
        const asyncRequestId = 41;
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        var pollCount = 0;

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          pollCount++;
          return Success(pollCount == 1 ? 0 : 1);
        });
        when(
          () => mockService.asyncGetResult(
            asyncRequestId,
            maxBufferBytes: any(named: 'maxBufferBytes'),
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(columns: [], rows: [], rowCount: 3),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeNonQuery(
          sql,
          null,
          timeout: const Duration(milliseconds: 1200),
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 3);
        verify(() => mockService.executeAsyncStart(pooledConnectionId, sql)).called(1);
        verify(() => mockService.asyncPoll(asyncRequestId)).called(2);
        verify(
          () => mockService.asyncGetResult(
            asyncRequestId,
            maxBufferBytes: any(named: 'maxBufferBytes'),
          ),
        ).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
        verifyNever(
          () => mockService.executePrepared(
            any(),
            any(),
            any(),
            any(),
          ),
        );
      },
    );

    test(
      'should fallback to prepared timeout path when async request start is unsupported for non-query',
      () async {
        const pooledConnectionId = 'pool-async-fallback-1';
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            UnsupportedFeatureError(message: 'async execution unsupported'),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeNonQuery(
          sql,
          null,
          timeout: const Duration(milliseconds: 1200),
        );

        expect(result.isSuccess(), isTrue);
        verify(() => mockService.executeAsyncStart(pooledConnectionId, sql)).called(1);
        verify(
          () => mockService.prepare(
            pooledConnectionId,
            sql,
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).called(1);
        final executePreparedCall = verify(
          () => mockService.executePrepared(
            pooledConnectionId,
            9001,
            captureAny(),
            captureAny(),
          ),
        );
        executePreparedCall.called(1);
        expect(executePreparedCall.captured[0], isNull);
        expect(executePreparedCall.captured[1], isA<StatementOptions>());
        verify(() => mockService.closeStatement(pooledConnectionId, 9001)).called(1);
      },
    );

    test(
      'should cancel native async non-query request on timeout and discard pooled connection',
      () async {
        const pooledConnectionId = 'pool-async-timeout-1';
        const asyncRequestId = 52;
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          return const Success(0);
        });
        when(() => mockConnectionPool.discard(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeNonQuery(
          sql,
          null,
          timeout: const Duration(milliseconds: 20),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        final queryFailure = failure! as domain.QueryExecutionFailure;
        expect(queryFailure.context['timeout'], isTrue);
        expect(queryFailure.context['reason'], 'query_timeout');
        expect(metrics.timeoutCancelSuccessCount, 1);
        verify(() => mockService.asyncCancel(asyncRequestId)).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verifyNever(() => mockConnectionPool.release(pooledConnectionId));
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
      },
    );

    test(
      'should keep prepared timeout path for parameterized query execution',
      () async {
        const pooledConnectionId = 'pool-prepared-query-1';
        const sql = 'SELECT * FROM users WHERE id = :id';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-prepared-query-1',
          agentId: config.agentId,
          query: sql,
          parameters: const {'id': 1},
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(
          request,
          timeout: const Duration(milliseconds: 1200),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(() => mockService.executeAsyncStart(any(), any()));
        verify(
          () => mockService.prepareNamed(
            pooledConnectionId,
            sql,
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).called(1);
        verify(
          () => mockService.executePreparedNamed(
            pooledConnectionId,
            9002,
            const {'id': 1},
            any(),
          ),
        ).called(1);
        verify(() => mockService.closeStatement(pooledConnectionId, 9002)).called(1);
      },
    );

    test(
      'should return timeout failure and discard pooled connection after best-effort cancel',
      () async {
        const pooledConnectionId = 'pool-timeout-1';
        const asyncRequestId = 41;
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-timeout-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          return const Success(0);
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.discard(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(
          request,
          timeout: const Duration(milliseconds: 20),
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        final queryFailure = failure! as domain.QueryExecutionFailure;
        expect(queryFailure.context['timeout'], isTrue);
        expect(queryFailure.context['reason'], 'query_timeout');
        expect(metrics.timeoutCancelSuccessCount, 1);
        verify(() => mockService.asyncCancel(asyncRequestId)).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verifyNever(() => mockConnectionPool.recycle(connectionString));
        verifyNever(() => mockConnectionPool.release(pooledConnectionId));
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
      },
    );

    test(
      'should still return timeout failure when best-effort cancel fails',
      () async {
        const pooledConnectionId = 'pool-timeout-2';
        const asyncRequestId = 42;
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-timeout-2',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          return const Success(0);
        });
        when(() => mockService.asyncCancel(asyncRequestId)).thenAnswer((_) async {
          return Failure(Exception('cancel failed'));
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.discard(pooledConnectionId)).thenAnswer((_) async {
          return Failure(Exception('discard failed'));
        });

        final result = await gateway.executeQuery(
          request,
          timeout: const Duration(milliseconds: 20),
        );

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        final queryFailure = failure! as domain.QueryExecutionFailure;
        expect(queryFailure.context['timeout'], isTrue);
        expect(queryFailure.context['reason'], 'query_timeout');
        expect(metrics.timeoutCancelFailureCount, greaterThanOrEqualTo(1));
        expect(metrics.poolReleaseFailureCount, greaterThanOrEqualTo(1));
        verify(() => mockService.asyncCancel(asyncRequestId)).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verifyNever(() => mockConnectionPool.recycle(connectionString));
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
      },
    );

    test(
      'should release every leased connection under concurrent executeQuery calls',
      () async {
        const sql = 'SELECT 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        var acquireCount = 0;
        final pooledIds = <String>[];

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfigMetadata()).thenAnswer((_) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          acquireCount++;
          final id = 'pool-concurrent-$acquireCount';
          pooledIds.add(id);
          return Success(id);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        ).thenAnswer((invocation) async {
          final connId = invocation.namedArguments[#connectionId] as String;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Success(
            QueryResult(
              columns: const ['id'],
              rows: <List<Object?>>[
                <Object?>[connId],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockConnectionPool.release(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final r1 = QueryRequest(
          id: 'req-concurrent-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );
        final r2 = QueryRequest(
          id: 'req-concurrent-2',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        final results = await Future.wait([
          gateway.executeQuery(r1),
          gateway.executeQuery(r2),
        ]);

        expect(results.every((r) => r.isSuccess()), isTrue);
        expect(pooledIds.length, 2);
        for (final id in pooledIds) {
          verify(() => mockConnectionPool.release(id)).called(1);
        }
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

