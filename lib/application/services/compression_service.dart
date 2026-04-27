import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_compressor.dart';
import 'package:result_dart/result_dart.dart';

class CompressionService {
  CompressionService(this._compressor);
  final ICompressor _compressor;

  Future<Result<QueryResponse>> compress(QueryResponse response) async {
    final result = await _compressor.compress(response.data);
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to compress response data',
          cause: failure,
          context: {'reason': failureMessage},
        ),
      );
    }

    final compressedResultSets = <QueryResultSet>[];
    final compressedByLogicalIndex = <int, QueryResultSet>{};
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
      final compressed = resultSet.copyWith(rows: compressedRows.getOrNull());
      compressedResultSets.add(compressed);
      compressedByLogicalIndex[resultSet.index] = compressed;
    }

    final compressedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          final compressed = compressedByLogicalIndex[item.resultSet!.index];
          if (compressed == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: compressed,
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
      final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to decompress response data',
          cause: failure,
          context: {'reason': failureMessage},
        ),
      );
    }

    final decompressedResultSets = <QueryResultSet>[];
    final decompressedByLogicalIndex = <int, QueryResultSet>{};
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
      final decompressed = resultSet.copyWith(rows: decompressedRows.getOrNull());
      decompressedResultSets.add(decompressed);
      decompressedByLogicalIndex[resultSet.index] = decompressed;
    }

    final decompressedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          final decompressed = decompressedByLogicalIndex[item.resultSet!.index];
          if (decompressed == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: decompressed,
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
