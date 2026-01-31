import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class HandleQueryRequest {
  HandleQueryRequest(
    this._databaseGateway,
    this._transportClient,
    this._normalizerService,
    this._compressionService,
  );
  final IDatabaseGateway _databaseGateway;
  final ITransportClient _transportClient;
  final QueryNormalizerService _normalizerService;
  final CompressionService _compressionService;

  Future<Result<void>> call(QueryRequest request) async {
    try {
      final queryResult = await _databaseGateway.executeQuery(request);

      return await queryResult.fold(
        (response) async {
          final normalizedResponse = await _normalizerService.normalize(
            response,
          );
          final compressionResult = await _compressionService.compress(
            normalizedResponse,
          );

          return await compressionResult.fold(
            (compressedResponse) async {
              return _transportClient.sendResponse(compressedResponse);
            },
            (failure) {
              final failureMessage = failure is domain.Failure
                  ? failure.message
                  : failure.toString();
              return Failure(
                domain.QueryExecutionFailure(
                  'Failed to compress response: $failureMessage',
                ),
              );
            },
          );
        },
        (failure) {
          return Failure(failure);
        },
      );
    } on Exception catch (e) {
      return Failure(
        domain.QueryExecutionFailure('Failed to handle query request: $e'),
      );
    }
  }
}
