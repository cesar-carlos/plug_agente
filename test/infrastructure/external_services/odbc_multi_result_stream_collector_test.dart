import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_multi_result_stream_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockQueryService extends Mock implements IQueryService {}

void main() {
  late _MockQueryService queries;

  setUp(() {
    queries = _MockQueryService();
  });

  test('forEachStreamQueryMulti streams items without pre-collecting', () async {
    when(() => queries.streamQueryMulti('c1', 'EXEC batch')).thenAnswer(
      (_) => Stream<Result<QueryResultMultiItem>>.fromIterable([
        const Success(
          QueryResultMultiItem.resultSet(
            QueryResult(columns: ['v'], rows: [[1]], rowCount: 1),
          ),
        ),
        const Success(QueryResultMultiItem.rowCount(3)),
      ]),
    );

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
  });

  test('collectStreamQueryMulti aggregates streamed items', () async {
    when(() => queries.streamQueryMulti('c1', 'EXEC batch')).thenAnswer(
      (_) => Stream<Result<QueryResultMultiItem>>.fromIterable([
        const Success(
          QueryResultMultiItem.resultSet(
            QueryResult(columns: ['v'], rows: [[1]], rowCount: 1),
          ),
        ),
        const Success(QueryResultMultiItem.rowCount(3)),
      ]),
    );

    final result = await collectStreamQueryMulti(queries, 'c1', 'EXEC batch');

    expect(result.isSuccess(), isTrue);
    final multi = result.getOrThrow();
    expect(multi.items.length, 2);
    expect(multi.rowCounts, [3]);
  });
}
