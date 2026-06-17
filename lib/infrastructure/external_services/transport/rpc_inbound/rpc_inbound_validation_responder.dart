import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_request_context.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_response_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_schema_validation_pipeline.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';

/// Maps schema validation failures to inbound error responses.
class RpcInboundValidationResponder {
  RpcInboundValidationResponder({
    required RpcInboundSchemaValidationPipeline schemaValidationPipeline,
    required RpcResponsePreparer responsePreparer,
    required RpcInboundResponseEmitter responseEmitter,
  }) : _schemaValidationPipeline = schemaValidationPipeline,
       _responsePreparer = responsePreparer,
       _responseEmitter = responseEmitter;

  final RpcInboundSchemaValidationPipeline _schemaValidationPipeline;
  final RpcResponsePreparer _responsePreparer;
  final RpcInboundResponseEmitter _responseEmitter;

  Future<void> sendSchemaValidationError(
    dynamic id,
    int code,
    String technicalMessage, {
    String? errorReason,
    Object? method,
  }) async {
    final errorResponse = _responsePreparer.buildErrorResponse(
      id: id,
      code: code,
      technicalMessage: technicalMessage,
      errorReason: errorReason,
    );
    await _responseEmitter.emit(
      errorResponse,
      methodsById: rpcInboundMethodsByIdForValidationError(
        id: id,
        method: method,
      ),
    );
  }

  Future<bool> validateBatchRequestJsonSchemasOrEmit(List<dynamic> data) async {
    final batchFailure = _schemaValidationPipeline.validateBatchEnvelope(data);
    if (batchFailure != null) {
      final firstId = data.whereType<Map<String, dynamic>>().firstOrNull?['id'];
      await sendSchemaValidationError(
        firstId,
        RpcErrorCode.invalidRequest,
        batchFailure.message,
        method: data.whereType<Map<String, dynamic>>().firstOrNull?['method'],
      );
      return false;
    }

    for (final item in data.whereType<Map<String, dynamic>>()) {
      if (!await validateSingleRequestJsonSchemasOrEmit(item)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> validateSingleRequestJsonSchemasOrEmit(Map<String, dynamic> requestMap) async {
    if (_schemaValidationPipeline.shouldSkipLargePayload(requestMap)) {
      _schemaValidationPipeline.recordSkippedLargePayload();
      final criticalFailure = _schemaValidationPipeline.validateCriticalFieldsWhenSkipping(requestMap);
      if (criticalFailure != null) {
        await sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.invalidParams,
          criticalFailure.message,
          method: requestMap['method'],
        );
        return false;
      }
      return true;
    }

    final envelopeFailure = _schemaValidationPipeline.validateRequestEnvelope(requestMap);
    if (envelopeFailure != null) {
      await sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidRequest,
        envelopeFailure.message,
        method: requestMap['method'],
      );
      return false;
    }

    final paramsFailure = _schemaValidationPipeline.validateRequestParams(requestMap);
    if (paramsFailure != null) {
      await sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidParams,
        paramsFailure.message,
        method: requestMap['method'],
      );
      return false;
    }

    return true;
  }
}
