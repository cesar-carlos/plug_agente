import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// JSON Schema validation for inbound RPC requests (envelope + per-method params).
class RpcInboundSchemaValidationPipeline {
  RpcInboundSchemaValidationPipeline({
    required JsonSchemaContractValidator? jsonSchemaValidator,
    required PayloadLogSummarizer logSummarizer,
    RpcMethodSchemaCatalog schemaCatalog = const RpcMethodSchemaCatalog(),
  }) : _jsonSchemaValidator = jsonSchemaValidator,
       _logSummarizer = logSummarizer,
       _schemaCatalog = schemaCatalog;

  final JsonSchemaContractValidator? _jsonSchemaValidator;
  final PayloadLogSummarizer _logSummarizer;
  final RpcMethodSchemaCatalog _schemaCatalog;

  bool shouldSkipLargePayload(Map<String, dynamic> requestMap) {
    return _logSummarizer.exceedsByteBudget(
      requestMap,
      ConnectionConstants.schemaValidationSkipAboveBytes,
    );
  }

  domain.Failure? validateBatchEnvelope(List<dynamic> data) {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return null;
    }

    final validation = jsonSchemaValidator.validate(
      schemaId: TransportSchemaIds.rpcBatchRequest,
      payload: data,
      direction: 'inbound',
    );
    if (validation.isError()) {
      return validation.exceptionOrNull()! as domain.Failure;
    }
    return null;
  }

  domain.Failure? validateRequestEnvelope(Map<String, dynamic> requestMap) {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return null;
    }

    final validation = jsonSchemaValidator.validate(
      schemaId: TransportSchemaIds.rpcRequest,
      payload: requestMap,
      direction: 'inbound',
    );
    if (validation.isError()) {
      return validation.exceptionOrNull()! as domain.Failure;
    }
    return null;
  }

  domain.Failure? validateRequestParams(Map<String, dynamic> requestMap) {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return null;
    }

    final method = requestMap['method'];
    if (method is! String || !requestMap.containsKey('params')) {
      return null;
    }

    final schemaId = _schemaCatalog.paramsSchemaFor(method);
    if (schemaId == null) {
      return null;
    }

    if (!jsonSchemaValidator.isLoaded(schemaId)) {
      return null;
    }

    final validation = jsonSchemaValidator.validate(
      schemaId: schemaId,
      payload: requestMap['params'],
      direction: 'inbound',
    );
    if (validation.isError()) {
      return validation.exceptionOrNull()! as domain.Failure;
    }
    return null;
  }

  domain.Failure? validateCriticalFieldsWhenSkipping(Map<String, dynamic> requestMap) {
    final jsonrpc = requestMap['jsonrpc'];
    if (jsonrpc != '2.0') {
      return domain.ValidationFailure('jsonrpc must be "2.0"');
    }

    final method = requestMap['method'];
    if (method is! String || method.trim().isEmpty) {
      return domain.ValidationFailure('method must be a non-empty string');
    }

    final params = requestMap['params'];
    if (params != null && params is! Map<String, dynamic>) {
      return domain.ValidationFailure('params must be an object when present');
    }

    if (params is Map<String, dynamic> && method.startsWith('sql.')) {
      final sql = params['sql'];
      if (sql != null && sql is! String) {
        return domain.ValidationFailure('params.sql must be a string');
      }
      final idempotencyKey = params['idempotency_key'];
      if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
        return domain.ValidationFailure('params.idempotency_key must be a non-empty string');
      }
    }

    return null;
  }

  void recordSkippedLargePayload() {
    _jsonSchemaValidator?.recordSkippedLargePayload(direction: 'inbound');
  }
}
