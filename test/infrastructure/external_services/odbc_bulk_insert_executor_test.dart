import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_native_bulk_insert_pool.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockNativeBulkInsertPool extends Mock implements IOdbcNativeBulkInsertPool {}

BulkInsertRequest _validRequest() {
  return const BulkInsertRequest(
    table: 'users',
    columns: [
      BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
      BulkInsertColumn(name: 'name', type: BulkInsertColumnType.text),
    ],
    rows: [
      [1, 'a'],
      [2, 'b'],
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(<String>[]);
    registerFallbackValue(<int>[]);
    registerFallbackValue(SavepointDialect.auto);
    registerFallbackValue(TransactionAccessMode.readWrite);
    registerFallbackValue(Duration.zero);
  });

  group('OdbcBulkInsertExecutor.validate', () {
    test('returns null for a well-formed request', () {
      expect(OdbcBulkInsertExecutor.validate(_validRequest()), isNull);
    });

    test('rejects an empty table', () {
      const request = BulkInsertRequest(
        table: '  ',
        columns: [BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32)],
        rows: [
          [1],
        ],
      );
      expect(OdbcBulkInsertExecutor.validate(request), isA<domain.ValidationFailure>());
    });

    test('rejects missing columns and missing rows', () {
      const noColumns = BulkInsertRequest(table: 't', columns: [], rows: []);
      const noRows = BulkInsertRequest(
        table: 't',
        columns: [BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32)],
        rows: [],
      );
      expect(OdbcBulkInsertExecutor.validate(noColumns), isA<domain.ValidationFailure>());
      expect(OdbcBulkInsertExecutor.validate(noRows), isA<domain.ValidationFailure>());
    });

    test('rejects an empty column name', () {
      const request = BulkInsertRequest(
        table: 't',
        columns: [BulkInsertColumn(name: ' ', type: BulkInsertColumnType.i32)],
        rows: [
          [1],
        ],
      );
      expect(OdbcBulkInsertExecutor.validate(request), isA<domain.ValidationFailure>());
    });

    test('rejects a row whose length does not match the column count', () {
      const request = BulkInsertRequest(
        table: 't',
        columns: [
          BulkInsertColumn(name: 'a', type: BulkInsertColumnType.i32),
          BulkInsertColumn(name: 'b', type: BulkInsertColumnType.i32),
        ],
        rows: [
          [1],
        ],
      );
      final failure = OdbcBulkInsertExecutor.validate(request)!;
      expect(failure.context['row_index'], 0);
      expect(failure.context['column_count'], 2);
    });
  });

  group('OdbcBulkInsertExecutor.executeDirect', () {
    late _MockOdbcService service;
    late MetricsCollector metrics;
    late OdbcBulkInsertExecutor executor;

    setUp(() {
      service = _MockOdbcService();
      metrics = MetricsCollector()..clear();
      final connectionManager = OdbcGatewayConnectionManager(
        service: service,
        connectionPool: _MockConnectionPool(),
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: 2,
          acquireTimeout: const Duration(seconds: 5),
          metricsCollector: metrics,
        ),
        metrics: metrics,
      );
      executor = OdbcBulkInsertExecutor(
        connectionManager: connectionManager,
        optionsResolver: OdbcConnectionOptionsResolver(MockOdbcConnectionSettings()),
        service: service,
        metrics: metrics,
        settings: MockOdbcConnectionSettings(),
      );
      when(
        () => service.beginTransaction(
          any(),
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      ).thenAnswer((_) async => const Success(7));
      when(() => service.commitTransaction(any(), any())).thenAnswer((_) async => const Success(unit));
      when(() => service.rollbackTransaction(any(), any())).thenAnswer((_) async => const Success(unit));
    });

    test('connects, bulk inserts and disconnects on the happy path', () async {
      when(() => service.connect(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Success(
          Connection(id: 'c1', connectionString: 'DSN=x', createdAt: DateTime(2024, 2, 3), isActive: true),
        ),
      );
      when(() => service.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((_) async => const Success(2));
      when(() => service.disconnect('c1')).thenAnswer((_) async => const Success(unit));

      final result = await executor.executeDirect(_validRequest(), 'DSN=x');

      expect(result.getOrNull(), 2);
      verify(() => service.disconnect('c1')).called(1);
    });

    test('chunks large bulk inserts and sums affected rows', () async {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_CHUNK_ROWS=2');
      when(() => service.connect(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Success(
          Connection(id: 'c1', connectionString: 'DSN=x', createdAt: DateTime(2024, 2, 3), isActive: true),
        ),
      );
      when(() => service.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((_) async => const Success(2));
      when(() => service.disconnect('c1')).thenAnswer((_) async => const Success(unit));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(5, (index) => [index]),
      );

      final result = await executor.executeDirect(request, 'DSN=x');

      expect(result.getOrNull(), 6);
      verify(() => service.bulkInsert(any(), any(), any(), any(), any())).called(3);
      verify(
        () => service.beginTransaction(
          'c1',
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      ).called(1);
      verify(() => service.commitTransaction('c1', 7)).called(1);
      expect(metrics.bulkInsertChunkedCount, 1);
      dotenv.clean();
    });

    test('rolls back chunked bulk insert when a later chunk fails', () async {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_CHUNK_ROWS=2');
      when(() => service.connect(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Success(
          Connection(id: 'c1', connectionString: 'DSN=x', createdAt: DateTime(2024, 2, 3), isActive: true),
        ),
      );
      var bulkCalls = 0;
      when(() => service.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((_) async {
        bulkCalls++;
        if (bulkCalls >= 2) {
          return Failure(Exception('chunk failed'));
        }
        return const Success(2);
      });
      when(() => service.disconnect('c1')).thenAnswer((_) async => const Success(unit));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(5, (index) => [index]),
      );

      final result = await executor.executeDirect(request, 'DSN=x');

      expect(result.isError(), isTrue);
      verify(() => service.rollbackTransaction('c1', 7)).called(1);
      verifyNever(() => service.commitTransaction(any(), any()));
      dotenv.clean();
    });

    test('executeOnConnection does not open a nested transaction for chunked inserts', () async {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_CHUNK_ROWS=2');
      when(() => service.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((_) async => const Success(2));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(5, (index) => [index]),
      );

      final result = await executor.executeOnConnection(connectionId: 'owned-1', request: request);

      expect(result.getOrNull(), 6);
      verifyNever(
        () => service.beginTransaction(
          any(),
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      );
      dotenv.clean();
    });

    test('uses bulkInsertParallel for large SQL Server loads when native pool is available', () async {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD=1000');
      final parallelPool = _MockNativeBulkInsertPool();
      final parallelExecutor = OdbcBulkInsertExecutor(
        connectionManager: OdbcGatewayConnectionManager(
          service: service,
          connectionPool: _MockConnectionPool(),
          directConnectionLimiter: DirectOdbcConnectionLimiter(
            maxConcurrent: 2,
            acquireTimeout: const Duration(seconds: 5),
            metricsCollector: metrics,
          ),
          metrics: metrics,
        ),
        optionsResolver: OdbcConnectionOptionsResolver(MockOdbcConnectionSettings()),
        service: service,
        metrics: metrics,
        settings: MockOdbcConnectionSettings(),
        parallelPool: parallelPool,
      );
      when(() => parallelPool.ensurePoolId(any())).thenAnswer((_) async => const Success(42));
      when(
        () => service.bulkInsertParallel(any(), any(), any(), any(), any(), parallelism: any(named: 'parallelism')),
      ).thenAnswer((_) async => const Success(1000));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(1500, (index) => [index]),
      );

      final result = await parallelExecutor.executeDirect(
        request,
        'DSN=sqlserver',
        databaseType: DatabaseType.sqlServer,
      );

      expect(result.getOrNull(), 1000);
      verify(() => parallelPool.ensurePoolId('DSN=sqlserver')).called(1);
      verify(
        () => service.bulkInsertParallel(42, any(), any(), any(), any(), parallelism: 4),
      ).called(1);
      verifyNever(() => service.connect(any(), options: any(named: 'options')));
      expect(metrics.bulkInsertParallelCount, 1);
      dotenv.clean();
    });

    test('parallel bulk failure is Failure and warns about partial writes', () async {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD=1000');
      final parallelPool = _MockNativeBulkInsertPool();
      final parallelExecutor = OdbcBulkInsertExecutor(
        connectionManager: OdbcGatewayConnectionManager(
          service: service,
          connectionPool: _MockConnectionPool(),
          directConnectionLimiter: DirectOdbcConnectionLimiter(
            maxConcurrent: 2,
            acquireTimeout: const Duration(seconds: 5),
            metricsCollector: metrics,
          ),
          metrics: metrics,
        ),
        optionsResolver: OdbcConnectionOptionsResolver(MockOdbcConnectionSettings()),
        service: service,
        metrics: metrics,
        settings: MockOdbcConnectionSettings(),
        parallelPool: parallelPool,
      );
      when(() => parallelPool.ensurePoolId(any())).thenAnswer((_) async => const Success(42));
      when(
        () => service.bulkInsertParallel(any(), any(), any(), any(), any(), parallelism: any(named: 'parallelism')),
      ).thenAnswer((_) async => Failure(Exception('worker 2 failed')));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(1500, (index) => [index]),
      );

      final result = await parallelExecutor.executeDirect(
        request,
        'DSN=sqlserver',
        databaseType: DatabaseType.sqlServer,
      );

      expect(result.isError(), isTrue);
      expect(result.isSuccess(), isFalse);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context['reason'], OdbcContextConstants.bulkInsertPartialWritesReason);
      expect(failure.context['partial_writes'], isTrue);
      expect(failure.message, contains('not atomic'));
      dotenv.clean();
    });

    test('requireAtomic refuses parallel and uses sequential transactional bulk', () async {
      dotenv.loadFromString(
        envString: 'ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD=1000\nODBC_BULK_INSERT_CHUNK_ROWS=1000',
      );
      final parallelPool = _MockNativeBulkInsertPool();
      final parallelExecutor = OdbcBulkInsertExecutor(
        connectionManager: OdbcGatewayConnectionManager(
          service: service,
          connectionPool: _MockConnectionPool(),
          directConnectionLimiter: DirectOdbcConnectionLimiter(
            maxConcurrent: 2,
            acquireTimeout: const Duration(seconds: 5),
            metricsCollector: metrics,
          ),
          metrics: metrics,
        ),
        optionsResolver: OdbcConnectionOptionsResolver(MockOdbcConnectionSettings()),
        service: service,
        metrics: metrics,
        settings: MockOdbcConnectionSettings(),
        parallelPool: parallelPool,
      );
      when(() => service.connect(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'c-atomic',
            connectionString: 'DSN=sqlserver',
            createdAt: DateTime(2024, 2, 3),
            isActive: true,
          ),
        ),
      );
      when(() => service.bulkInsert(any(), any(), any(), any(), any())).thenAnswer((invocation) async {
        final rowCount = invocation.positionalArguments[4] as int;
        return Success(rowCount);
      });
      when(() => service.disconnect('c-atomic')).thenAnswer((_) async => const Success(unit));

      final request = BulkInsertRequest(
        table: 'users',
        columns: const [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: List<List<dynamic>>.generate(1500, (index) => [index]),
      );

      final result = await parallelExecutor.executeDirect(
        request,
        'DSN=sqlserver',
        databaseType: DatabaseType.sqlServer,
        requireAtomic: true,
      );

      expect(result.getOrNull(), 1500);
      verifyNever(() => parallelPool.ensurePoolId(any()));
      verifyNever(
        () => service.bulkInsertParallel(any(), any(), any(), any(), any(), parallelism: any(named: 'parallelism')),
      );
      verify(
        () => service.beginTransaction(
          'c-atomic',
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      ).called(1);
      verify(() => service.commitTransaction('c-atomic', 7)).called(1);
      dotenv.clean();
    });

    test('maps a connect failure to a connection failure', () async {
      when(
        () => service.connect(any(), options: any(named: 'options')),
      ).thenAnswer((_) async => Failure(Exception('no route to host')));

      final result = await executor.executeDirect(_validRequest(), 'DSN=x');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.Failure>());
      verifyNever(() => service.bulkInsert(any(), any(), any(), any(), any()));
    });
  });
}
