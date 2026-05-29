import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

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
      );
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

    test('maps a connect failure to a connection failure', () async {
      when(() => service.connect(any(), options: any(named: 'options')))
          .thenAnswer((_) async => Failure(Exception('no route to host')));

      final result = await executor.executeDirect(_validRequest(), 'DSN=x');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.Failure>());
      verifyNever(() => service.bulkInsert(any(), any(), any(), any(), any()));
    });
  });
}
