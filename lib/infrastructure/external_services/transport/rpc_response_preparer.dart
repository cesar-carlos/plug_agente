import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/protocol_version.dart';
import 'package:plug_agente/core/constants/rpc_response_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

/// Builds the wire form of [RpcResponse] objects, attaches W3C/legacy trace
/// metadata mirrored from the request, validates the outgoing contract (with
/// a soft size cap), signs payloads when running outside the binary transport,
/// and centralises the construction of error responses.
///
/// Stays free of any Socket.IO type so the transport client only needs to feed
/// it the request/response, then emit the JSON returned by [prepareForSend] /
/// [validateOutgoing].
class RpcResponsePreparer {
  RpcResponsePreparer({
    required FeatureFlags featureFlags,
    required PayloadLogSummarizer logSummarizer,
    required RpcContractValidator contractValidator,
    required ProtocolConfig Function() protocolProvider,
    required bool Function() usesBinaryTransport,
    required String Function() agentIdProvider,
    JsonSchemaContractValidator? jsonSchemaValidator,
    RpcMethodSchemaCatalog schemaCatalog = const RpcMethodSchemaCatalog(),
    PayloadSigner? payloadSigner,
  }) : _featureFlags = featureFlags,
       _logSummarizer = logSummarizer,
       _contractValidator = contractValidator,
       _protocolProvider = protocolProvider,
       _usesBinaryTransport = usesBinaryTransport,
       _agentIdProvider = agentIdProvider,
       _jsonSchemaValidator = jsonSchemaValidator,
       _schemaCatalog = schemaCatalog,
       _payloadSigner = payloadSigner;

  final FeatureFlags _featureFlags;
  final PayloadLogSummarizer _logSummarizer;
  final RpcContractValidator _contractValidator;
  final ProtocolConfig Function() _protocolProvider;
  final bool Function() _usesBinaryTransport;
  final String Function() _agentIdProvider;
  final JsonSchemaContractValidator? _jsonSchemaValidator;
  final RpcMethodSchemaCatalog _schemaCatalog;
  final PayloadSigner? _payloadSigner;

  /// Serialises a single [RpcResponse] into the wire `Map<String, dynamic>`,
  /// optionally adding the `api_version` / `meta` envelope and a non-binary
  /// HMAC `signature` when the agent runs in JSON-only mode with signing on.
  Map<String, dynamic> prepareForSend(RpcResponse response) {
    late final Map<String, dynamic> json;
    if (_featureFlags.enableSocketApiVersionMeta) {
      final existingMeta = Map<String, dynamic>.from(
        response.meta?.toJson() ?? const <String, dynamic>{},
      );
      // Preserve the wire-level `request_id` already propagated by
      // [attachRequestTrace] (mirrors `request.meta.requestId`). Falls back to
      // `response.id` for code paths that build responses without trace
      // attachment, keeping today's behavior intact while staying compatible
      // with the future `clientRequestIdEcho` extension where `response.id`
      // would carry the consumer's id and `request_id` must remain the hub
      // wire correlator. See
      // `plug_server/docs/plug_agente/03_performance_roadmap.md` item 8.
      final propagatedRequestId = existingMeta['request_id'] as String?;
      json = <String, dynamic>{
        'jsonrpc': response.jsonrpc,
        'id': response.id,
        if (response.result != null) 'result': response.result,
        if (response.error != null) 'error': response.error!.toJson(),
        'api_version': ProtocolVersion.apiVersion,
        'meta': <String, dynamic>{
          ...existingMeta,
          'agent_id': _agentIdProvider(),
          'request_id': propagatedRequestId ?? response.id?.toString(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };
    } else {
      json = <String, dynamic>{
        'jsonrpc': response.jsonrpc,
        'id': response.id,
        if (response.result != null) 'result': response.result,
        if (response.error != null) 'error': response.error!.toJson(),
        if (response.apiVersion != null) 'api_version': response.apiVersion,
        if (response.meta != null) 'meta': response.meta!.toJson(),
      };
    }
    if (!_usesBinaryTransport() && _featureFlags.enablePayloadSigning) {
      final signer = _payloadSigner;
      if (signer != null) {
        json['signature'] = signer.sign(json).toJson();
      }
    }
    return json;
  }

  /// Validates the outgoing wire payload against the contract (single response
  /// or batch). Returns the original payload on success or a fallback minimal
  /// error response when validation fails. Returns [Failure] only when even the
  /// fallback cannot be validated (extremely defensive — should never happen).
  ///
  /// Skips validation entirely when feature flags disable it or when the
  /// payload exceeds [ConnectionConstants.socketOutgoingContractValidationMaxBytes]
  /// (UTF-8 bytes), to keep CPU bounded for large result sets.
  Result<dynamic> validateOutgoing(
    dynamic payload, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) {
    if (!_featureFlags.enableSocketSchemaValidation) {
      return Success(payload as Object);
    }
    if (!_featureFlags.enableSocketOutgoingContractValidation) {
      return Success(payload as Object);
    }

    const softCap = ConnectionConstants.socketOutgoingContractValidationMaxBytes;
    if (softCap > 0 && _logSummarizer.exceedsByteBudget(payload, softCap)) {
      _jsonSchemaValidator?.recordSkippedLargePayload(direction: 'outbound');
      return Success(payload as Object);
    }

    final sanitizedPayload = RpcWireMap.sanitizeRpcResponseWirePayload(payload);
    final validation = sanitizedPayload is List<dynamic>
        ? _contractValidator.validateBatchResponse(sanitizedPayload)
        : sanitizedPayload is Map<String, dynamic>
        ? _contractValidator.validateResponse(sanitizedPayload)
        : _contractValidator.validateResponse(const <String, dynamic>{});
    if (validation.isSuccess()) {
      final schemaValidation = _validateOutgoingWithJsonSchemas(
        sanitizedPayload,
        methodsById: methodsById,
      );
      if (schemaValidation == null) {
        return Success(sanitizedPayload as Object);
      }
      return _fallbackForInvalidOutgoingPayload(schemaValidation);
    }

    final failure = validation.exceptionOrNull()! as domain.Failure;
    return _fallbackForInvalidOutgoingPayload(failure);
  }

  domain.Failure? _validateOutgoingWithJsonSchemas(
    dynamic payload, {
    required Map<Object?, String> methodsById,
  }) {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return null;
    }

    final envelopeSchemaId = payload is List<dynamic>
        ? TransportSchemaIds.rpcBatchResponse
        : TransportSchemaIds.rpcResponse;
    final envelopeValidation = jsonSchemaValidator.validate(
      schemaId: envelopeSchemaId,
      payload: payload,
      direction: 'outbound',
    );
    if (envelopeValidation.isError()) {
      return envelopeValidation.exceptionOrNull()! as domain.Failure;
    }

    if (payload is List<dynamic>) {
      for (final item in payload.whereType<Map<String, dynamic>>()) {
        final failure = _validateSingleResponseJsonSchema(
          item,
          methodsById: methodsById,
        );
        if (failure != null) {
          return failure;
        }
      }
      return null;
    }

    if (payload is Map<String, dynamic>) {
      return _validateSingleResponseJsonSchema(
        payload,
        methodsById: methodsById,
      );
    }

    return domain.ValidationFailure.withContext(
      message: 'Outgoing RPC response payload must be a response object or batch response array',
      context: {'payloadType': payload.runtimeType.toString()},
    );
  }

  domain.Failure? _validateSingleResponseJsonSchema(
    Map<String, dynamic> response, {
    required Map<Object?, String> methodsById,
  }) {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return null;
    }

    final error = response['error'];
    if (error != null) {
      final errorValidation = jsonSchemaValidator.validate(
        schemaId: TransportSchemaIds.rpcError,
        payload: error,
        direction: 'outbound',
      );
      if (errorValidation.isError()) {
        return errorValidation.exceptionOrNull()! as domain.Failure;
      }
      return null;
    }

    if (!response.containsKey('result')) {
      return null;
    }

    final method = methodsById[response['id']];
    if (method == null) {
      return null;
    }
    final schemaId = _schemaCatalog.resultSchemaFor(method);
    if (schemaId == null) {
      return null;
    }

    final resultValidation = jsonSchemaValidator.validate(
      schemaId: schemaId,
      payload: response['result'],
      direction: 'outbound',
    );
    if (resultValidation.isError()) {
      return resultValidation.exceptionOrNull()! as domain.Failure;
    }
    return null;
  }

  Result<dynamic> _fallbackForInvalidOutgoingPayload(domain.Failure failure) {
    AppLogger.error(
      'Outgoing rpc:response payload is invalid: ${failure.message}',
    );
    final fallback = prepareForSend(
      buildErrorResponse(
        id: null,
        code: RpcErrorCode.internalError,
        technicalMessage: RpcResponseConstants.outgoingContractValidationFailedTechnicalMessage,
      ),
    );

    final fallbackValidation = _contractValidator.validateResponse(fallback);
    if (fallbackValidation.isError()) {
      final fallbackFailure = fallbackValidation.exceptionOrNull()! as domain.Failure;
      AppLogger.error(
        'Fallback rpc:response payload is invalid: ${fallbackFailure.message}',
      );
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Fallback rpc:response payload is invalid',
          cause: fallbackFailure,
          context: {'rpc_error_code': RpcErrorCode.internalError},
        ),
      );
    }
    return Success(fallback as Object);
  }

  /// Mirrors trace context (W3C `traceparent`/`tracestate` and/or legacy
  /// `trace_id`) from [request] onto [response] meta, controlled by the
  /// `traceContext` extension negotiated with the hub.
  RpcResponse attachRequestTrace(RpcRequest request, RpcResponse response) {
    final requestMeta = request.meta;
    final responseMeta = response.meta;
    final supportedTraceContext = _protocolProvider().negotiatedExtensions['traceContext'];
    final traceModes = supportedTraceContext is List<dynamic>
        ? supportedTraceContext.whereType<String>().toSet()
        : {'w3c-trace-context', 'legacy-trace-id'};
    final mergedMeta = RpcProtocolMeta(
      traceId: traceModes.contains('legacy-trace-id') ? responseMeta?.traceId ?? requestMeta?.traceId : null,
      traceParent: traceModes.contains('w3c-trace-context')
          ? responseMeta?.traceParent ?? requestMeta?.traceParent
          : null,
      traceState: traceModes.contains('w3c-trace-context') ? responseMeta?.traceState ?? requestMeta?.traceState : null,
      requestId: responseMeta?.requestId ?? requestMeta?.requestId,
      agentId: responseMeta?.agentId,
      timestamp: responseMeta?.timestamp,
    );

    if (response.isError) {
      return RpcResponse.error(
        id: response.id,
        error: response.error!,
        apiVersion: response.apiVersion,
        meta: mergedMeta,
      );
    }

    return RpcResponse.success(
      id: response.id,
      result: response.result,
      apiVersion: response.apiVersion,
      meta: mergedMeta,
    );
  }

  /// Constructs an error [RpcResponse] with a proper code message and the
  /// machine-readable `data` envelope (technical message + reason).
  RpcResponse buildErrorResponse({
    required dynamic id,
    required int code,
    required String technicalMessage,
    String? errorReason,
  }) {
    return RpcResponse.error(
      id: id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: technicalMessage,
          reason: errorReason,
        ),
      ),
    );
  }

  /// Verifies the HMAC signature attached to an inbound JSON-only payload
  /// (legacy non-binary transport). When signatures are not required, unsigned
  /// payloads are accepted but signed payloads still must be verifiable.
  bool verifyIncomingSignature(Map<String, dynamic> payload) {
    final sigJson = payload['signature'] as Map<String, dynamic>?;
    final signatureRequired = _featureFlags.requireIncomingPayloadSignatures;
    if (_payloadSigner == null) {
      return sigJson == null && !signatureRequired;
    }
    if (sigJson == null) return !signatureRequired;
    final signature = PayloadSignature.fromJson(sigJson);
    return _payloadSigner.verify(payload, signature);
  }
}
