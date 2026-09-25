import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Incremental consumer for coalesced multi-result items.
typedef OdbcMultiResultItemHandler = Future<void> Function(QueryResultMultiItem item);

QueryResult _appendResultBatch(QueryResult current, QueryResult next) {
  return QueryResult(
    columns: current.columns,
    rows: <List<dynamic>>[...current.rows, ...next.rows],
    rowCount: current.rowCount + next.rowCount,
    outputParamValues: current.outputParamValues,
    columnsMetadata: current.columnsMetadata ?? next.columnsMetadata,
  );
}

domain_failures.Failure _mapStreamQueryMultiError(
  Object error, {
  required String operation,
}) {
  if (error is domain_failures.Failure) {
    return error;
  }

  return OdbcFailureMapper.mapStreamingError(
    error,
    operation: operation,
  );
}

/// Streams bounded `streamQueryMultiBatches` fetches and coalesces continuation
/// batches into one [QueryResult] per cursor before calling [onItem].
Future<Result<void>> forEachStreamQueryMulti(
  IQueryService queries,
  String connectionId,
  String sql,
  OdbcMultiResultItemHandler onItem, {
  int fetchSize = OdbcStreamingNativeOptions.odbcFastDefaultFetchSize,
  int chunkSize = OdbcStreamingNativeOptions.materializedMultiResultChunkSizeBytes,
}) async {
  QueryResult? pendingResultSet;

  Future<Result<void>> flushPending() async {
    final pending = pendingResultSet;
    if (pending == null) {
      return const Success(unit);
    }
    pendingResultSet = null;
    try {
      await onItem(QueryResultMultiItem.resultSet(pending));
      return const Success(unit);
    } on Object catch (error) {
      return Failure(
        _mapStreamQueryMultiError(
          error,
          operation: 'streamQueryMulti.onItem',
        ),
      );
    }
  }

  await for (final itemResult in queries.streamQueryMultiBatches(
    connectionId,
    sql,
    fetchSize: fetchSize,
    chunkSize: chunkSize,
  )) {
    if (itemResult.isError()) {
      return Failure(
        _mapStreamQueryMultiError(
          itemResult.exceptionOrNull()!,
          operation: 'streamQueryMultiBatches',
        ),
      );
    }

    final batch = itemResult.getOrThrow();
    final resultSet = batch.resultSet;
    if (resultSet != null) {
      if (batch.isContinuationBatch && pendingResultSet != null) {
        pendingResultSet = _appendResultBatch(pendingResultSet!, resultSet);
        continue;
      }
      final flushed = await flushPending();
      if (flushed.isError()) {
        return flushed;
      }
      pendingResultSet = resultSet;
      continue;
    }

    final flushed = await flushPending();
    if (flushed.isError()) {
      return flushed;
    }
    final rowCount = batch.rowCount;
    if (rowCount == null) {
      continue;
    }
    try {
      await onItem(QueryResultMultiItem.rowCount(rowCount));
    } on Object catch (error) {
      return Failure(
        _mapStreamQueryMultiError(
          error,
          operation: 'streamQueryMulti.onItem',
        ),
      );
    }
  }

  return flushPending();
}

/// Aggregates `streamQueryMulti` items into a [QueryResultMulti] when callers
/// need full materialization (RPC multi-result responses).
Future<Result<QueryResultMulti>> collectStreamQueryMulti(
  IQueryService queries,
  String connectionId,
  String sql, {
  int fetchSize = OdbcStreamingNativeOptions.odbcFastDefaultFetchSize,
  int chunkSize = OdbcStreamingNativeOptions.materializedMultiResultChunkSizeBytes,
}) async {
  final items = <QueryResultMultiItem>[];

  final streamed = await forEachStreamQueryMulti(
    queries,
    connectionId,
    sql,
    (item) async {
      items.add(item);
    },
    fetchSize: fetchSize,
    chunkSize: chunkSize,
  );
  if (streamed.isError()) {
    return Failure(streamed.exceptionOrNull()!);
  }

  return Success(QueryResultMulti(items: items));
}
