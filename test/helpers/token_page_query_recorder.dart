import 'package:drift/drift.dart';

class TokenPageQueryRecorder extends QueryInterceptor {
  ({String sql, List<Object?> arguments})? lastPageQuery;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('client_token_cache_table') && statement.contains('ORDER BY')) {
      lastPageQuery = (sql: statement, arguments: List.of(args));
    }
    return executor.runSelect(statement, args);
  }

  Future<List<String>> explainPageQuery(QueryExecutor executor) async {
    final query = lastPageQuery!;
    final rows = await executor.runSelect('EXPLAIN QUERY PLAN ${query.sql}', query.arguments);
    return rows.map((row) => row['detail']! as String).toList();
  }
}
