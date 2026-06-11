import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockNativeCompatibleConnectionPool extends Mock
    implements IConnectionPool, INativeCompatibleConnectionPoolAcquire {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(const StatementOptions());
    registerFallbackValue(const ConnectionAcquireOptions());
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockOdbcService service;
  late _MockConnectionPool pool;
  late MetricsCollector metrics;
  late OdbcGatewayConnectionManager connectionManager;
  late OdbcReadOnlyBatchParallelExecutor executor;
  late DatabaseConfig databaseConfig;

  setUp(() {
    service = _MockOdbcService();
    when(() => service.executeAsyncStart(any(), any())).thenAnswer(
      (_) async => const Failure(
        UnsupportedFeatureError(message: 'async execution unsupported'),
      ),
    );
    pool = _MockConnectionPool();
    metrics = MetricsCollector()..clear();
    connectionManager = OdbcGatewayConnectionManager(
      service: service,
      connectionPool: pool,
      directConnectionLimiter: DirectOdbcConnectionLimiter(
        maxConcurrent: 2,
        acquireTimeout: const Duration(seconds: 1),
      ),
      metrics: metrics,
    );
    final settings = MockOdbcConnectionSettings(poolSize: 4);
    final discarded = <String>[];
    final statementExecutor = OdbcStatementExecutor(
      service: service,
      metrics: metrics,
      markConnectionForDiscard: discarded.add,
    );
    final queryRunner = OdbcQueryRunner(
      service: service,
      metrics: metrics,
      statementExecutor: statementExecutor,
      resultEncodingExecutor: OdbcResultEncodingExecutor(service),
      markConnectionForDiscard: discarded.add,
    );
    executor = OdbcReadOnlyBatchParallelExecutor(
      connectionManager: connectionManager,
      queryRunner: queryRunner,
      optionsResolver: OdbcConnectionOptionsResolver(settings),
      metrics: metrics,
      parallelSemaphore: PoolSemaphore(2),
      uuid: const Uuid(),
      recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId}) {},
    );
    databaseConfig = DatabaseConfig.sqlServer(
      driverName: 'ODBC Driver 18 for SQL Server',
      username: 'sa',
      password: 'secret',
      database: 'db',
      server: 'localhost',
      port: 1433,
    );
  });

  group('OdbcReadOnlyBatchParallelExecutor', () {
    test('safeParallelismForPoolSize uses half the pool rounded down', () {
      expect(OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(4), 2);
      expect(OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(1), 1);
    });

    test('executes commands with capped worker parallelism', () async {
      const connectionString = 'DSN=Prod';
      var acquireCount = 0;
      var activeExecutions = 0;
      var peakExecutions = 0;

      when(() => pool.acquire(connectionString, options: any(named: 'options'))).thenAnswer((_) async {
        acquireCount++;
        return Success('worker-$acquireCount');
      });
      when(() => pool.release(any())).thenAnswer((_) async => const Success(unit));
      when(
        () => service.executeQuery(
          any(),
          connectionId: any(named: 'connectionId'),
        ),
      ).thenAnswer((_) async {
        activeExecutions++;
        peakExecutions = peakExecutions < activeExecutions ? activeExecutions : peakExecutions;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        activeExecutions--;
        return const Success(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });

      final result = await executor.execute(
        agentId: 'agent',
        commands: const [
          SqlCommand(sql: 'SELECT 1'),
          SqlCommand(sql: 'SELECT 2'),
          SqlCommand(sql: 'SELECT 3'),
        ],
        connectionString: connectionString,
        databaseConfig: databaseConfig,
        options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 4),
        timeout: const Duration(seconds: 5),
        batchSqlPreview: 'SELECT 1; SELECT 2; SELECT 3',
        poolSize: 4,
      );

      expect(result.isSuccess(), isTrue);
      expect(acquireCount, 2);
      expect(peakExecutions, 2);
      final items = result.getOrThrow();
      expect(items.every((item) => item.ok), isTrue);
      expect(items.length, 3);
    });

    test('returns Success with per-item failures for partial command errors', () async {
      const connectionString = 'DSN=Prod';
      when(() => pool.acquire(connectionString, options: any(named: 'options'))).thenAnswer(
        (_) async => const Success('worker-1'),
      );
      when(() => pool.release(any())).thenAnswer((_) async => const Success(unit));
      when(
        () => service.executeQuery(
          'SELECT bad',
          connectionId: any(named: 'connectionId'),
        ),
      ).thenAnswer((_) async => Failure(Exception('syntax error')));
      when(
        () => service.executeQuery(
          'SELECT good',
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

      final result = await executor.execute(
        agentId: 'agent',
        commands: const [
          SqlCommand(sql: 'SELECT good'),
          SqlCommand(sql: 'SELECT bad'),
        ],
        connectionString: connectionString,
        databaseConfig: databaseConfig,
        options: const SqlExecutionOptions(),
        timeout: const Duration(seconds: 5),
        batchSqlPreview: 'SELECT good; SELECT bad',
        poolSize: 2,
      );

      expect(result.isSuccess(), isTrue);
      final items = result.getOrThrow();
      expect(items[0].ok, isTrue);
      expect(items[1].ok, isFalse);
      expect(items[1].error, isNotEmpty);
    });

    test('marks remaining items failed when the batch deadline elapses', () async {
      const connectionString = 'DSN=Prod';
      when(() => pool.acquire(connectionString, options: any(named: 'options'))).thenAnswer(
        (_) async => const Success('worker-1'),
      );
      when(() => pool.release(any())).thenAnswer((_) async => const Success(unit));
      when(
        () => service.executeQuery(
          any(),
          connectionId: any(named: 'connectionId'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return const Success(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });

      final result = await executor.execute(
        agentId: 'agent',
        commands: const [
          SqlCommand(sql: 'SELECT 1'),
          SqlCommand(sql: 'SELECT 2'),
          SqlCommand(sql: 'SELECT 3'),
        ],
        connectionString: connectionString,
        databaseConfig: databaseConfig,
        options: const SqlExecutionOptions(),
        timeout: const Duration(milliseconds: 30),
        batchSqlPreview: 'SELECT 1; SELECT 2; SELECT 3',
        poolSize: 2,
      );

      expect(result.isSuccess(), isTrue);
      final items = result.getOrThrow();
      expect(items.where((item) => item.ok).length, lessThan(3));
      expect(items.any((item) => !item.ok && item.error!.contains('timeout')), isTrue);
    });

    test('uses native-compatible acquire when enabled', () async {
      const connectionString = 'DSN=Prod';
      final nativePool = _MockNativeCompatibleConnectionPool();
      final nativeConnectionManager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: nativePool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 1),
        ),
        metrics: metrics,
      );
      final nativeExecutor = OdbcReadOnlyBatchParallelExecutor(
        connectionManager: nativeConnectionManager,
        queryRunner: OdbcQueryRunner(
          service: service,
          metrics: metrics,
          statementExecutor: OdbcStatementExecutor(
            service: service,
            metrics: metrics,
            markConnectionForDiscard: nativeConnectionManager.markConnectionForDiscard,
          ),
          resultEncodingExecutor: OdbcResultEncodingExecutor(service),
          markConnectionForDiscard: nativeConnectionManager.markConnectionForDiscard,
        ),
        optionsResolver: OdbcConnectionOptionsResolver(MockOdbcConnectionSettings(poolSize: 4)),
        metrics: metrics,
        parallelSemaphore: PoolSemaphore(2),
        uuid: const Uuid(),
        recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId}) {},
      );

      when(
        () => nativePool.acquireNativeCompatible(
          connectionString,
          leaseFallbackOptions: any(named: 'leaseFallbackOptions'),
          acquireTimeout: any(named: 'acquireTimeout'),
        ),
      ).thenAnswer((_) async => const Success('native-worker-1'));
      when(() => nativePool.release('native-worker-1')).thenAnswer((_) async => const Success(unit));
      when(
        () => service.executeQuery(
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

      final result = await nativeExecutor.execute(
        agentId: 'agent',
        commands: const [
          SqlCommand(sql: 'SELECT 1'),
          SqlCommand(sql: 'SELECT 2'),
        ],
        connectionString: connectionString,
        databaseConfig: databaseConfig,
        options: const SqlExecutionOptions(),
        timeout: const Duration(seconds: 5),
        batchSqlPreview: 'SELECT 1; SELECT 2',
        poolSize: 4,
        allowNativeCompatibleAcquire: true,
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
    });

    test('returns typed failure when worker pool warm-up exceeds deadline', () async {
      const connectionString = 'DSN=Prod';
      when(() => pool.acquire(connectionString, options: any(named: 'options'))).thenAnswer(
        (_) => Future<Result<String>>.delayed(
          const Duration(milliseconds: 50),
          () => const Success('worker-1'),
        ),
      );

      final result = await executor.execute(
        agentId: 'agent',
        commands: const [
          SqlCommand(sql: 'SELECT 1'),
          SqlCommand(sql: 'SELECT 2'),
        ],
        connectionString: connectionString,
        databaseConfig: databaseConfig,
        options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 2),
        timeout: Duration.zero,
        batchSqlPreview: 'SELECT 1; SELECT 2',
        poolSize: 4,
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.QueryExecutionFailure>());
    });
  });
}
