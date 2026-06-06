import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart' show SqlCommand, SqlCommandResult, SqlExecutionOptions;
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class _MockGateway extends Mock implements IDatabaseGateway {}

class _MockNormalizer extends Mock implements QueryNormalizerService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      QueryRequest(
        id: 'fb',
        agentId: 'a',
        query: 'SELECT 1',
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(const SqlExecutionOptions());
    registerFallbackValue(const Duration(seconds: 7));
  });

  group('ExecuteSqlBatch', () {
    test('should truncate rows per command using options.maxRows', () async {
      final gateway = _MockGateway();
      final normalizer = _MockNormalizer();
      final batch = ExecuteSqlBatch(gateway, normalizer);

      final wideData = List<Map<String, dynamic>>.generate(
        5,
        (int i) => {'n': i},
      );

      when(
        () => gateway.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      ).thenAnswer(
        (_) async => Success([
          SqlCommandResult.success(
            index: 0,
            rows: wideData,
            rowCount: wideData.length,
          ),
        ]),
      );
      when(
        () => normalizer.normalizeRows(
          any(
            that: isA<List<Map<String, dynamic>>>().having(
              (rows) => rows.length,
              'length',
              2,
            ),
          ),
          keyCache: any(named: 'keyCache'),
        ),
      ).thenAnswer(
        (invocation) => invocation.positionalArguments.first as List<Map<String, dynamic>>,
      );

      final out = await batch.call(
        'agent',
        [const SqlCommand(sql: 'SELECT n FROM t')],
        options: const SqlExecutionOptions(maxRows: 2),
      );

      expect(out.isSuccess(), isTrue);
      final rows = out.getOrNull()!.single.rows!;
      expect(rows, hasLength(2));
      expect(rows[0]['n'], 0);
      expect(rows[1]['n'], 1);
      verify(
        () => gateway.executeBatch(
          'agent',
          any(
            that: isA<List<SqlCommand>>().having(
              (List<SqlCommand> c) => c.length,
              'length',
              1,
            ),
          ),
          options: const SqlExecutionOptions(maxRows: 2),
        ),
      ).called(1);
      verifyNever(() => gateway.executeQuery(any()));
      verify(
        () => normalizer.normalizeRows(
          any(
            that: isA<List<Map<String, dynamic>>>().having(
              (rows) => rows.length,
              'length',
              2,
            ),
          ),
          keyCache: any(named: 'keyCache'),
        ),
      ).called(1);
    });

    test('should delegate to gateway when transaction is true', () async {
      final gateway = _MockGateway();
      final normalizer = _MockNormalizer();
      final batch = ExecuteSqlBatch(gateway, normalizer);

      when(
        () => gateway.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => Success([
          SqlCommandResult.success(
            index: 0,
            rows: const [
              {'x': 1},
            ],
          ),
        ]),
      );

      final out = await batch.call(
        'agent',
        [const SqlCommand(sql: 'UPDATE t SET x=1')],
        options: const SqlExecutionOptions(transaction: true),
      );

      expect(out.isSuccess(), isTrue);
      verify(
        () => gateway.executeBatch(
          'agent',
          any(
            that: isA<List<SqlCommand>>().having(
              (List<SqlCommand> c) => c.length,
              'length',
              1,
            ),
          ),
          options: any(
            named: 'options',
            that: isA<SqlExecutionOptions>().having(
              (SqlExecutionOptions o) => o.transaction,
              'transaction',
              isTrue,
            ),
          ),
        ),
      ).called(1);
      verifyNever(() => gateway.executeQuery(any()));
    });

    test(
      'should forward timeout to non-transactional batch execution',
      () async {
        final gateway = _MockGateway();
        final normalizer = _MockNormalizer();
        final batch = ExecuteSqlBatch(gateway, normalizer);

        when(
          () => gateway.executeBatch(
            any(),
            any(),
            database: any(named: 'database'),
            options: any(named: 'options'),
            timeout: any(named: 'timeout'),
            sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
          ),
        ).thenAnswer((invocation) async {
          return const Success(<SqlCommandResult>[]);
        });

        await batch.call(
          'agent',
          [
            const SqlCommand(sql: 'SELECT 1'),
            const SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(seconds: 30),
        );

        verify(
          () => gateway.executeBatch(
            'agent',
            any(
              that: isA<List<SqlCommand>>().having(
                (List<SqlCommand> c) => c.length,
                'length',
                2,
              ),
            ),
            timeout: const Duration(seconds: 30),
          ),
        ).called(1);
        verifyNever(() => gateway.executeQuery(any()));
      },
    );

    test('should fail fast on invalid SQL before calling gateway', () async {
      final gateway = _MockGateway();
      final normalizer = _MockNormalizer();
      final batch = ExecuteSqlBatch(gateway, normalizer);

      final out = await batch.call(
        'agent',
        [
          const SqlCommand(sql: 'SELECT 1'),
          const SqlCommand(sql: 'DROP TABLE users; SELECT 1'),
        ],
      );

      expect(out.isError(), isTrue);
      out.fold(
        (_) => fail('expected failure'),
        (failure) {
          final validationFailure = failure as domain.ValidationFailure;
          expect(validationFailure.context['operation'], 'batch_validation');
          expect(validationFailure.context['index'], 1);
        },
      );
      verifyNever(
        () => gateway.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      );
    });

    test('should cap read-only batch parallelism to pool policy', () async {
      final gateway = _MockGateway();
      final normalizer = _MockNormalizer();
      final batch = ExecuteSqlBatch(
        gateway,
        normalizer,
        poolSizeProvider: () => 8,
      );

      when(
        () => gateway.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      ).thenAnswer((_) async => const Success(<SqlCommandResult>[]));

      await batch.call(
        'agent',
        [
          const SqlCommand(sql: 'SELECT 1'),
          const SqlCommand(sql: 'SELECT 2'),
        ],
        options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 99),
      );

      final expectedCap = ConnectionConstants.readOnlyBatchParallelismForPoolSize(8);
      verify(
        () => gateway.executeBatch(
          'agent',
          any(),
          options: any(
            named: 'options',
            that: predicate<SqlExecutionOptions>(
              (options) => options.maxParallelReadOnlyBatchItems == expectedCap,
            ),
          ),
        ),
      ).called(1);
    });

    test(
      'should forward non-transactional batch failure from gateway',
      () async {
        final gateway = _MockGateway();
        final normalizer = _MockNormalizer();
        final batch = ExecuteSqlBatch(gateway, normalizer);

        when(
          () => gateway.executeBatch(
            any(),
            any(),
            database: any(named: 'database'),
            options: any(named: 'options'),
            timeout: any(named: 'timeout'),
            sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
          ),
        ).thenAnswer(
          (_) async => Failure(domain.QueryExecutionFailure('batch failed')),
        );

        final out = await batch.call(
          'agent',
          [
            const SqlCommand(sql: 'SELECT 1'),
            const SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(milliseconds: 100),
        );

        expect(out.isError(), isTrue);
        verifyNever(() => gateway.executeQuery(any()));
      },
    );
  });
}
