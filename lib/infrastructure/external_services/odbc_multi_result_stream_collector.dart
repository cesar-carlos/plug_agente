import 'package:odbc_fast/odbc_fast.dart';
import 'package:result_dart/result_dart.dart';

/// Incremental consumer for `streamQueryMulti` items.
typedef OdbcMultiResultItemHandler = Future<void> Function(QueryResultMultiItem item);

/// Streams `streamQueryMulti` items to [onItem] without building a full
/// [QueryResultMulti] first.
Future<Result<void>> forEachStreamQueryMulti(
  IQueryService queries,
  String connectionId,
  String sql,
  OdbcMultiResultItemHandler onItem,
) async {
  await for (final itemResult in queries.streamQueryMulti(connectionId, sql)) {
    if (itemResult.isError()) {
      return Failure(itemResult.exceptionOrNull()!);
    }
    try {
      await onItem(itemResult.getOrThrow());
    } on Exception catch (error) {
      return Failure(error);
    } on Object catch (error) {
      return Failure(Exception(error.toString()));
    }
  }

  return const Success(unit);
}

/// Aggregates `streamQueryMulti` items into a [QueryResultMulti] when callers
/// need full materialization (RPC multi-result responses).
Future<Result<QueryResultMulti>> collectStreamQueryMulti(
  IQueryService queries,
  String connectionId,
  String sql,
) async {
  final items = <QueryResultMultiItem>[];

  final streamed = await forEachStreamQueryMulti(
    queries,
    connectionId,
    sql,
    (item) async {
      items.add(item);
    },
  );
  if (streamed.isError()) {
    return Failure(streamed.exceptionOrNull()!);
  }

  return Success(QueryResultMulti(items: items));
}
