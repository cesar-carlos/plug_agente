import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart'
    show SqlCommand, SqlCommandResult, SqlExecutionOptions;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

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
    registerFallbackValue(
      QueryResponse(
        id: 'fb',
        requestId: 'r',
        agentId: 'a',
        data: const [],
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
      final batch = ExecuteSqlBatch(gateway, normalizer, const Uuid());

      final wideData = List<Map<String, dynamic>>.generate(
        5,
        (int i) => {'n': i},
      );
      final response = QueryResponse(
        id: 'q1',
        requestId: 'r1',
        agentId: 'agent',
        data: wideData,
        timestamp: DateTime.now(),
      );

      when(() => gateway.executeQuery(any())).thenAnswer(
        (_) async => Success(response),
      );
      when(() => normalizer.normalize(any())).thenAnswer(
        (invocation) => invocation.positionalArguments[0] as QueryResponse,
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
    });

    test('should delegate to gateway when transaction is true', () async {
      final gateway = _MockGateway();
      final normalizer = _MockNormalizer();
      final batch = ExecuteSqlBatch(gateway, normalizer, const Uuid());

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
      'should pass shrinking ODBC timeouts between non-transactional commands',
      () async {
        final gateway = _MockGateway();
        final normalizer = _MockNormalizer();
        final batch = ExecuteSqlBatch(gateway, normalizer, const Uuid());

        final timeouts = <Duration?>[];
        when(
          () => gateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
          ),
        ).thenAnswer((invocation) async {
          const sym = Symbol('timeout');
          timeouts.add(
            invocation.namedArguments.containsKey(sym)
                ? invocation.namedArguments[sym] as Duration?
                : null,
          );
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return Success(
            QueryResponse(
              id: 'q',
              requestId: 'r',
              agentId: 'a',
              data: const [],
              timestamp: DateTime.now(),
            ),
          );
        });
        when(() => normalizer.normalize(any())).thenAnswer(
          (invocation) => invocation.positionalArguments[0] as QueryResponse,
        );

        await batch.call(
          'agent',
          [
            const SqlCommand(sql: 'SELECT 1'),
            const SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(seconds: 30),
        );

        expect(timeouts, hasLength(2));
        final t0 = timeouts[0];
        final t1 = timeouts[1];
        if (t0 == null || t1 == null) {
          fail('expected non-null ODBC timeouts');
        }
        expect(t1, lessThan(t0));
      },
    );

    test(
      'should fail when batch budget is exhausted before a command',
      () async {
        final gateway = _MockGateway();
        final normalizer = _MockNormalizer();
        final batch = ExecuteSqlBatch(gateway, normalizer, const Uuid());

        when(
          () => gateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          return Success(
            QueryResponse(
              id: 'q',
              requestId: 'r',
              agentId: 'a',
              data: const [],
              timestamp: DateTime.now(),
            ),
          );
        });
        when(() => normalizer.normalize(any())).thenAnswer(
          (invocation) => invocation.positionalArguments[0] as QueryResponse,
        );

        final out = await batch.call(
          'agent',
          [
            const SqlCommand(sql: 'SELECT 1'),
            const SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(milliseconds: 1),
        );

        expect(out.isError(), isTrue);
        verify(
          () => gateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
          ),
        ).called(1);
      },
    );
  });
}
