import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_rewriter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockConnectionPool extends Mock implements IConnectionPool {}

class MockNativeCompatibleConnectionPool extends Mock
    implements IConnectionPool, INativeCompatibleConnectionPoolAcquire {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(const ConnectionAcquireOptions());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<Object?>[]);
  });

  group('OdbcBatchExecutionOrchestrator', () {
    late MockOdbcService mockService;
    late MockConnectionPool mockConnectionPool;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcBatchExecutionOrchestrator orchestrator;
    late Future<Result<Config>> Function() resolveActiveConfigFn;

    setUp(() {
      dotenv.clean();
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
        service: mockService,
        metrics: metrics,
        statementExecutor: statementExecutor,
        resultEncodingExecutor: OdbcResultEncodingExecutor(mockService),
        markConnectionForDiscard: connectionManager.markConnectionForDiscard,
      );
      final txManager = OdbcBatchTransactionManager(
        service: mockService,
        metrics: metrics,
        onRollbackUnconfirmed: connectionManager.markConnectionForDiscard,
      );
      final optionsResolver = OdbcConnectionOptionsResolver(mockSettings);
      final bulkInsertExecutor = OdbcBulkInsertExecutor(
        connectionManager: connectionManager,
        optionsResolver: optionsResolver,
        service: mockService,
        metrics: metrics,
        settings: mockSettings,
      );
      final parallelSemaphore = PoolSemaphore(
        OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(mockSettings.poolSize),
      );
      final readOnlyBatchParallelExecutor = OdbcReadOnlyBatchParallelExecutor(
        connectionManager: connectionManager,
        queryRunner: queryRunner,
        optionsResolver: optionsResolver,
        metrics: metrics,
        parallelSemaphore: parallelSemaphore,
        uuid: const Uuid(),
        recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId, method = 'sql.executeBatch'}) {},
      );

      resolveActiveConfigFn = () async => Failure(Exception('no config'));

      orchestrator = OdbcBatchExecutionOrchestrator(
        connectionManager: connectionManager,
        txManager: txManager,
        bulkInsertExecutor: bulkInsertExecutor,
        queryRunner: queryRunner,
        statementExecutor: statementExecutor,
        optionsResolver: optionsResolver,
        nativeCompatiblePolicy: NativeCompatibleAcquirePolicy(),
        metrics: metrics,
        readOnlyBatchParallelExecutor: readOnlyBatchParallelExecutor,
        readOnlyBatchParallelSemaphore: parallelSemaphore,
        uuid: const Uuid(),
        poolSize: mockSettings.poolSize,
        ensureInitialized: () async => const Success(unit),
        resolveActiveConfig: () => resolveActiveConfigFn(),
        buildDatabaseConfig: _buildDatabaseConfig,
        resolveConnectionString: _resolveConnectionString,
        recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId, method = 'sql.executeBatch'}) {},
        recordExecutionFailure: ({
          required QueryRequest request,
          required OdbcPreparedQueryExecution preparedExecution,
          required String errorMessage,
          required bool executedInDb,
          String method = 'sql.execute',
        }) {},
      );

      when(() => mockConnectionPool.discard(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConnectionPool.release(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(
        () => mockConnectionPool.getActiveCount(
          connectionString: any(named: 'connectionString'),
        ),
      ).thenAnswer((_) async {
        return const Success(0);
      });
      when(() => mockService.rollbackTransaction(any(), any())).thenAnswer((_) async {
        return const Success(unit);
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
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: any(named: 'connectionId'),
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
      'should infer TransactionAccessMode.readOnly for transactional batches containing only SELECTs',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-tx-1';
        final config = _buildConfig(connectionString);
        resolveActiveConfigFn = () async => Success(config);

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
        ).thenAnswer((_) async => const Success(1));
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
        when(() => mockService.commitTransaction(ownedId, 1)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          agentId: config.agentId,
          commands: const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(
            transaction: true,
            timeoutMs: 1200,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(() => mockConnectionPool.acquire(any(), options: any(named: 'options')));
        verify(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: SavepointDialect.auto,
            accessMode: TransactionAccessMode.readOnly,
            lockTimeout: const Duration(milliseconds: 1200),
          ),
        ).called(1);
        expect(metrics.transactionalBatchDirectPathCount, 1);
      },
    );

    test(
      'should recover non-transactional batch command after invalid pooled connection id',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const firstConnectionId = 'pool-batch-1';
        const secondConnectionId = 'pool-batch-2';
        final config = _buildConfig(connectionString);
        resolveActiveConfigFn = () async => Success(config);
        var acquireCount = 0;

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

        final result = await orchestrator.execute(
          agentId: config.agentId,
          commands: const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(timeoutMs: 1200),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        verify(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).called(2);
        verify(() => mockConnectionPool.discard(firstConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(connectionString)).called(1);
      },
    );

    test(
      'should route large homogeneous insert batches to native bulk insert',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const directConnectionId = 'bulk-route-direct-1';
        final config = _buildConfig(connectionString);
        resolveActiveConfigFn = () async => Success(config);
        final commands = List<SqlCommand>.generate(
          50,
          (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
        );

        when(() => mockService.connect(any(), options: any(named: 'options'))).thenAnswer(
          (_) async => Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime(2024, 2, 3),
              isActive: true,
            ),
          ),
        );
        when(() => mockService.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((_) async {
          return const Success(50);
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          agentId: config.agentId,
          commands: commands,
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrThrow(), hasLength(commands.length));
        expect(metrics.batchBulkInsertRoutedCount, 1);
        verify(() => mockService.bulkInsert(any(), any(), any(), any(), any())).called(1);
        verifyNever(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options')));
      },
    );

    test(
      'should use native-compatible pool path for SQL Server transactional DML batch',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const nativeId = 'native-tx-1';
        final config = _buildConfig(connectionString);
        final nativePool = MockNativeCompatibleConnectionPool();
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        final nativeOrchestrator = _createOrchestratorWithPool(
          mockService: mockService,
          connectionPool: nativePool,
          metrics: metrics,
          mockSettings: mockSettings,
          featureFlags: featureFlags,
          resolveActiveConfig: () async => Success(config),
        );

        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((_) async => const Success(nativeId));
        when(() => nativePool.release(nativeId)).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.beginTransaction(
            nativeId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async => const Success(7));
        when(
          () => mockService.executeQuery(
            'INSERT INTO audit_log (id) VALUES (1)',
            connectionId: nativeId,
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: [],
              rows: [],
              rowCount: 1,
            ),
          ),
        );
        when(() => mockService.commitTransaction(nativeId, 7)).thenAnswer((_) async => const Success(unit));

        final result = await nativeOrchestrator.execute(
          agentId: config.agentId,
          commands: const [SqlCommand(sql: 'INSERT INTO audit_log (id) VALUES (1)')],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).called(1);
        verifyNever(() => nativePool.acquire(connectionString, options: any(named: 'options')));
        verifyNever(() => mockService.connect(any(), options: any(named: 'options')));
        expect(metrics.transactionalBatchNativePoolPathCount, 1);
      },
    );

    test(
      'should fallback transactional DML batch to direct path when native begin fails',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const nativeId = 'native-tx-stale-1';
        const ownedId = 'owned-tx-fallback-1';
        final config = _buildConfig(connectionString);
        final nativePool = MockNativeCompatibleConnectionPool();
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        final nativeOrchestrator = _createOrchestratorWithPool(
          mockService: mockService,
          connectionPool: nativePool,
          metrics: metrics,
          mockSettings: mockSettings,
          featureFlags: featureFlags,
          resolveActiveConfig: () async => Success(config),
        );

        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((_) async => const Success(nativeId));
        when(() => nativePool.discard(nativeId)).thenAnswer((_) async => const Success(unit));
        when(() => nativePool.recycle(connectionString)).thenAnswer((_) async => const Success(unit));
        when(
          () => mockService.beginTransaction(
            nativeId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer(
          (_) async => const Failure(
            ConnectionError(
              message: 'Invalid connection ID: stale transaction handle',
              nativeCode: 100000,
            ),
          ),
        );
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer(
          (_) async => Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          ),
        );
        when(
          () => mockService.beginTransaction(
            ownedId,
            savepointDialect: any(named: 'savepointDialect'),
            accessMode: any(named: 'accessMode'),
            lockTimeout: any(named: 'lockTimeout'),
          ),
        ).thenAnswer((_) async => const Success(9));
        when(
          () => mockService.executeQuery(
            'INSERT INTO audit_log (id) VALUES (1)',
            connectionId: ownedId,
          ),
        ).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: [],
              rows: [],
              rowCount: 1,
            ),
          ),
        );
        when(() => mockService.commitTransaction(ownedId, 9)).thenAnswer((_) async => const Success(unit));
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async => const Success(unit));

        final result = await nativeOrchestrator.execute(
          agentId: config.agentId,
          commands: const [SqlCommand(sql: 'INSERT INTO audit_log (id) VALUES (1)')],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isSuccess(), isTrue);
        expect(metrics.transactionalBatchNativePoolFallbackCount, 1);
        expect(metrics.transactionalBatchDirectPathCount, 1);
      },
    );

    test(
      'should use native-compatible pool path for read-only parallel batch when gate is on',
      () async {
        dotenv.loadFromString(envString: 'ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED=true');
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final nativePool = MockNativeCompatibleConnectionPool();
        final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
        await featureFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
        final nativeOrchestrator = _createOrchestratorWithPool(
          mockService: mockService,
          connectionPool: nativePool,
          metrics: metrics,
          mockSettings: mockSettings,
          featureFlags: featureFlags,
          resolveActiveConfig: () async => Success(config),
        );
        var nativeAcquireCount = 0;

        when(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).thenAnswer((_) async {
          nativeAcquireCount++;
          return Success('native-readonly-$nativeAcquireCount');
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
              columns: ['v'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );

        final result = await nativeOrchestrator.execute(
          agentId: config.agentId,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          options: const SqlExecutionOptions(
            timeoutMs: 0,
            maxParallelReadOnlyBatchItems: 2,
          ),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => nativePool.acquireNativeCompatible(
            connectionString,
            leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
            acquireTimeout: any(named: 'acquireTimeout'),
          ),
        ).called(2);
        verifyNever(() => nativePool.acquire(connectionString, options: any(named: 'options')));
        expect(metrics.readOnlyBatchNativePoolPathCount, 1);
        expect(metrics.readOnlyBatchParallelCount, 1);
      },
    );

    test(
      'should recommend sql.bulkInsert when route threshold is above batch size',
      () async {
        dotenv.loadFromString(envString: 'ODBC_BATCH_BULK_INSERT_ROUTE_THRESHOLD=100');
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const pooledConnectionId = 'pool-batch-insert-recommendation-1';
        final config = _buildConfig(connectionString);
        resolveActiveConfigFn = () async => Success(config);
        final commands = List<SqlCommand>.generate(
          50,
          (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
        );

        when(() => mockConnectionPool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
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
              columns: [],
              rows: [],
              rowCount: 1,
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          agentId: config.agentId,
          commands: commands,
        );

        expect(result.isSuccess(), isTrue);
        expect(metrics.batchBulkInsertRecommendedCount, 1);
        expect(metrics.batchBulkInsertRoutedCount, 0);
      },
    );
  });
}

OdbcBatchExecutionOrchestrator _createOrchestratorWithPool({
  required MockOdbcService mockService,
  required IConnectionPool connectionPool,
  required MetricsCollector metrics,
  required MockOdbcConnectionSettings mockSettings,
  required FeatureFlags featureFlags,
  required Future<Result<Config>> Function() resolveActiveConfig,
}) {
  when(() => connectionPool.discard(any())).thenAnswer((_) async {
    return const Success(unit);
  });
  when(() => connectionPool.release(any())).thenAnswer((_) async {
    return const Success(unit);
  });
  when(() => connectionPool.recycle(any())).thenAnswer((_) async {
    return const Success(unit);
  });
  when(
    () => connectionPool.getActiveCount(
      connectionString: any(named: 'connectionString'),
    ),
  ).thenAnswer((_) async {
    return const Success(0);
  });

  final connectionManager = OdbcGatewayConnectionManager(
    service: mockService,
    connectionPool: connectionPool,
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
    service: mockService,
    metrics: metrics,
    statementExecutor: statementExecutor,
    resultEncodingExecutor: OdbcResultEncodingExecutor(mockService),
    markConnectionForDiscard: connectionManager.markConnectionForDiscard,
  );
  final txManager = OdbcBatchTransactionManager(
    service: mockService,
    metrics: metrics,
    onRollbackUnconfirmed: connectionManager.markConnectionForDiscard,
  );
  final optionsResolver = OdbcConnectionOptionsResolver(mockSettings);
  final bulkInsertExecutor = OdbcBulkInsertExecutor(
    connectionManager: connectionManager,
    optionsResolver: optionsResolver,
    service: mockService,
    metrics: metrics,
    settings: mockSettings,
  );
  final parallelSemaphore = PoolSemaphore(
    OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(mockSettings.poolSize),
  );
  return OdbcBatchExecutionOrchestrator(
    connectionManager: connectionManager,
    txManager: txManager,
    bulkInsertExecutor: bulkInsertExecutor,
    queryRunner: queryRunner,
    statementExecutor: statementExecutor,
    optionsResolver: optionsResolver,
    nativeCompatiblePolicy: NativeCompatibleAcquirePolicy(featureFlags: featureFlags),
    metrics: metrics,
    readOnlyBatchParallelExecutor: OdbcReadOnlyBatchParallelExecutor(
      connectionManager: connectionManager,
      queryRunner: queryRunner,
      optionsResolver: optionsResolver,
      metrics: metrics,
      parallelSemaphore: parallelSemaphore,
      uuid: const Uuid(),
      recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId, method = 'sql.executeBatch'}) {},
    ),
    readOnlyBatchParallelSemaphore: parallelSemaphore,
    uuid: const Uuid(),
    poolSize: mockSettings.poolSize,
    ensureInitialized: () async => const Success(unit),
    resolveActiveConfig: resolveActiveConfig,
    buildDatabaseConfig: _buildDatabaseConfig,
    resolveConnectionString: _resolveConnectionString,
    recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId, method = 'sql.executeBatch'}) {},
    recordExecutionFailure: ({
      required QueryRequest request,
      required OdbcPreparedQueryExecution preparedExecution,
      required String errorMessage,
      required bool executedInDb,
      String method = 'sql.execute',
    }) {},
  );
}

DatabaseConfig _buildDatabaseConfig(Config config) {
  return DatabaseConfig(
    driverName: config.odbcDriverName,
    username: config.username,
    password: config.password ?? '',
    database: config.databaseName,
    server: config.host,
    port: config.port,
    databaseType: switch (config.driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => DatabaseType.sqlServer,
    },
  );
}

String _resolveConnectionString(
  Config config,
  DatabaseConfig databaseConfig, {
  String? databaseOverride,
}) {
  return OdbcConnectionStringRewriter.resolve(
    config,
    databaseConfig,
    databaseOverride: databaseOverride,
  );
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
