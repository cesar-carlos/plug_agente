import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Incremental consumer for `streamQueryMulti` items.
typedef OdbcMultiResultItemHandler = Future<void> Function(QueryResultMultiItem item);

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

/// Streams `streamQueryMulti` items to [onItem] without building a full
/// [QueryResultMulti] first.
Future<Result<void>> forEachStreamQueryMulti(
  IQueryService queries,
  String connectionId,
  String sql,
  OdbcMultiResultItemHandler onItem, {
  int fetchSize = OdbcStreamingNativeOptions.odbcFastDefaultFetchSize,
  int chunkSize = OdbcStreamingNativeOptions.materializedMultiResultChunkSizeBytes,
}) async {
  await for (final itemResult in queries.streamQueryMulti(
    connectionId,
    sql,
    fetchSize: fetchSize,
    chunkSize: chunkSize,
  )) {
    if (itemResult.isError()) {
      return Failure(
        _mapStreamQueryMultiError(
          itemResult.exceptionOrNull()!,
          operation: 'streamQueryMulti',
        ),
      );
    }
    try {
      await onItem(itemResult.getOrThrow());
    } on Object catch (error) {
      return Failure(
        _mapStreamQueryMultiError(
          error,
          operation: 'streamQueryMulti.onItem',
        ),
      );
    }
  }

  return const Success(unit);
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
