import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/infrastructure/external_services/odbc_multi_result_stream_collector.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockQueryService extends Mock implements IQueryService {}

void main() {
  late _MockQueryService queries;

  setUp(() {
    queries = _MockQueryService();
  });

  Stream<rd.Result<QueryResultMultiItem>> multiItemsStream() {
    return Stream<rd.Result<QueryResultMultiItem>>.fromIterable([
      const rd.Success(
        QueryResultMultiItem.resultSet(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        ),
      ),
      const rd.Success(QueryResultMultiItem.rowCount(3)),
    ]);
  }

  test('forEachStreamQueryMulti streams items without pre-collecting', () async {
    when(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer((_) => multiItemsStream());

    final seen = <QueryResultMultiItem>[];
    final result = await forEachStreamQueryMulti(
      queries,
      'c1',
      'EXEC batch',
      (item) async {
        seen.add(item);
      },
    );

    expect(result.isSuccess(), isTrue);
    expect(seen.length, 2);
    verify(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
      ),
    ).called(1);
  });

  test('forEachStreamQueryMulti forwards custom fetchSize and chunkSize', () async {
    when(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer((_) => multiItemsStream());

    final result = await forEachStreamQueryMulti(
      queries,
      'c1',
      'EXEC batch',
      (_) async {},
      fetchSize: 250,
      chunkSize: 128 * 1024,
    );

    expect(result.isSuccess(), isTrue);
    verify(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: 250,
        chunkSize: 128 * 1024,
      ),
    ).called(1);
  });

  test('collectStreamQueryMulti aggregates streamed items', () async {
    when(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer((_) => multiItemsStream());

    final result = await collectStreamQueryMulti(queries, 'c1', 'EXEC batch');

    expect(result.isSuccess(), isTrue);
    final multi = result.getOrThrow();
    expect(multi.items.length, 2);
    expect(multi.rowCounts, [3]);
  });

  test('forEachStreamQueryMulti maps stream errors to typed failures', () async {
    when(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream<rd.Result<QueryResultMultiItem>>.fromIterable([
        rd.Failure(Exception('SQL syntax error near SELECT')),
      ]),
    );

    final result = await forEachStreamQueryMulti(
      queries,
      'c1',
      'EXEC batch',
      (_) async {},
    );

    expect(result.isError(), isTrue);
    final failure = result.exceptionOrNull()! as domain_failures.Failure;
    expect(failure, isA<domain_failures.ValidationFailure>());
    expect(failure.context['odbc_message'], contains('SQL syntax error'));
    expect(failure.context['user_message'], isNotEmpty);
  });

  test('forEachStreamQueryMulti maps handler errors to typed failures', () async {
    when(
      () => queries.streamQueryMulti(
        'c1',
        'EXEC batch',
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream<rd.Result<QueryResultMultiItem>>.fromIterable([
        const rd.Success(
          QueryResultMultiItem.resultSet(
            QueryResult(
              columns: ['v'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        ),
      ]),
    );

    final result = await forEachStreamQueryMulti(
      queries,
      'c1',
      'EXEC batch',
      (_) async {
        throw StateError('handler failed');
      },
    );

    expect(result.isError(), isTrue);
    final failure = result.exceptionOrNull()! as domain_failures.Failure;
    expect(failure, isA<domain_failures.QueryExecutionFailure>());
    expect(failure.context['odbc_message'], contains('handler failed'));
  });
}
