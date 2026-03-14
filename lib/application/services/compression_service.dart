import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/compression/gzip_compressor.dart';
import 'package:result_dart/result_dart.dart';

class CompressionService {
  CompressionService(this._compressor);
  final GzipCompressor _compressor;

  Future<Result<QueryResponse>> compress(QueryResponse response) async {
    final result = await _compressor.compress(response.data);
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      final failureMessage = failure is domain.Failure
          ? failure.message
          : failure.toString();
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to compress response data',
          cause: failure,
          context: {'reason': failureMessage},
        ),
      );
    }

    final compressedResultSets = <QueryResultSet>[];
    for (final resultSet in response.resultSets) {
      final compressedRows = await _compressor.compress(resultSet.rows);
      if (compressedRows.isError()) {
        return Failure(
          domain.CompressionFailure.withContext(
            message: 'Failed to compress response data',
            cause: compressedRows.exceptionOrNull(),
            context: {'reason': 'result_set_compression_failed'},
          ),
        );
      }
      compressedResultSets.add(
        resultSet.copyWith(rows: compressedRows.getOrNull()),
      );
    }

    final compressedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: compressedResultSets[item.resultSet!.index],
          );
        })
        .toList(growable: false);

    return Success(
      QueryResponse(
        id: response.id,
        requestId: response.requestId,
        agentId: response.agentId,
        data: result.getOrNull()!,
        affectedRows: response.affectedRows,
        timestamp: response.timestamp,
        error: response.error,
        columnMetadata: response.columnMetadata,
        pagination: response.pagination,
        resultSets: compressedResultSets,
        items: compressedItems,
      ),
    );
  }

  Future<Result<QueryResponse>> decompress(QueryResponse response) async {
    final result = await _compressor.decompress(response.data);
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      final failureMessage = failure is domain.Failure
          ? failure.message
          : failure.toString();
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to decompress response data',
          cause: failure,
          context: {'reason': failureMessage},
        ),
      );
    }

    final decompressedResultSets = <QueryResultSet>[];
    for (final resultSet in response.resultSets) {
      final decompressedRows = await _compressor.decompress(resultSet.rows);
      if (decompressedRows.isError()) {
        return Failure(
          domain.CompressionFailure.withContext(
            message: 'Failed to decompress response data',
            cause: decompressedRows.exceptionOrNull(),
            context: {'reason': 'result_set_decompression_failed'},
          ),
        );
      }
      decompressedResultSets.add(
        resultSet.copyWith(rows: decompressedRows.getOrNull()),
      );
    }

    final decompressedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: decompressedResultSets[item.resultSet!.index],
          );
        })
        .toList(growable: false);

    return Success(
      QueryResponse(
        id: response.id,
        requestId: response.requestId,
        agentId: response.agentId,
        data: result.getOrNull()!,
        affectedRows: response.affectedRows,
        timestamp: response.timestamp,
        error: response.error,
        columnMetadata: response.columnMetadata,
        pagination: response.pagination,
        resultSets: decompressedResultSets,
        items: decompressedItems,
      ),
    );
  }
}
