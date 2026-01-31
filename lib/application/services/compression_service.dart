import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/compression/gzip_compressor.dart';
import 'package:result_dart/result_dart.dart';

class CompressionService {
  CompressionService(this._compressor);
  final GzipCompressor _compressor;

  Future<Result<QueryResponse>> compress(QueryResponse response) async {
    final result = await _compressor.compress(response.data);

    return result.fold(
      (compressedData) => Success(
        QueryResponse(
          id: response.id,
          requestId: response.requestId,
          agentId: response.agentId,
          data: compressedData,
          affectedRows: response.affectedRows,
          timestamp: response.timestamp,
          error: response.error,
        ),
      ),
      (failure) {
        final failureMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        return Failure(
          domain.CompressionFailure(
            'Failed to compress response data: $failureMessage',
          ),
        );
      },
    );
  }

  Future<Result<QueryResponse>> decompress(QueryResponse response) async {
    final result = await _compressor.decompress(response.data);

    return result.fold(
      (decompressedData) => Success(
        QueryResponse(
          id: response.id,
          requestId: response.requestId,
          agentId: response.agentId,
          data: decompressedData,
          affectedRows: response.affectedRows,
          timestamp: response.timestamp,
          error: response.error,
        ),
      ),
      (failure) {
        final failureMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        return Failure(
          domain.CompressionFailure(
            'Failed to decompress response data: $failureMessage',
          ),
        );
      },
    );
  }
}
