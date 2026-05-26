import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
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

    // Compress all result sets in parallel — each _compressor.compress call
    // is an isolate round-trip, so parallel dispatch removes N-1 serial delays
    // on multi-result responses.
    final compressedResultSets = <QueryResultSet>[];
    final compressedByLogicalIndex = <int, QueryResultSet>{};
    if (response.resultSets.isNotEmpty) {
      final futures = response.resultSets
          .map((resultSet) => _compressor.compress(resultSet.rows).then((r) => (resultSet: resultSet, rows: r)))
          .toList(growable: false);
      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry.rows.isError()) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to compress response data',
              cause: entry.rows.exceptionOrNull(),
              context: {'reason': SqlPipelineContextConstants.resultSetCompressionFailedReason},
            ),
          );
        }
        final compressed = entry.resultSet.copyWith(rows: entry.rows.getOrNull());
        compressedResultSets.add(compressed);
        compressedByLogicalIndex[entry.resultSet.index] = compressed;
      }
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
        startedAt: response.startedAt,
        wasTruncated: response.wasTruncated,
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
    if (response.resultSets.isNotEmpty) {
      final futures = response.resultSets
          .map((resultSet) => _compressor.decompress(resultSet.rows).then((r) => (resultSet: resultSet, rows: r)))
          .toList(growable: false);
      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry.rows.isError()) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to decompress response data',
              cause: entry.rows.exceptionOrNull(),
              context: {'reason': SqlPipelineContextConstants.resultSetDecompressionFailedReason},
            ),
          );
        }
        final decompressed = entry.resultSet.copyWith(rows: entry.rows.getOrNull());
        decompressedResultSets.add(decompressed);
        decompressedByLogicalIndex[entry.resultSet.index] = decompressed;
      }
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
        startedAt: response.startedAt,
        wasTruncated: response.wasTruncated,
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
