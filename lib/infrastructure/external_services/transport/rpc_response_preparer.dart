import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/protocol_version.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

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
    PayloadSigner? payloadSigner,
  }) : _featureFlags = featureFlags,
       _logSummarizer = logSummarizer,
       _contractValidator = contractValidator,
       _protocolProvider = protocolProvider,
       _usesBinaryTransport = usesBinaryTransport,
       _agentIdProvider = agentIdProvider,
       _payloadSigner = payloadSigner;

  final FeatureFlags _featureFlags;
  final PayloadLogSummarizer _logSummarizer;
  final RpcContractValidator _contractValidator;
  final ProtocolConfig Function() _protocolProvider;
  final bool Function() _usesBinaryTransport;
  final String Function() _agentIdProvider;
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
      json = <String, dynamic>{
        'jsonrpc': response.jsonrpc,
        'id': response.id,
        if (response.result != null) 'result': response.result,
        if (response.error != null) 'error': response.error!.toJson(),
        'api_version': ProtocolVersion.apiVersion,
        'meta': <String, dynamic>{
          ...existingMeta,
          'agent_id': _agentIdProvider(),
          'request_id': response.id?.toString(),
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
  /// or batch). Returns the original payload on success, a fallback minimal
  /// error response on validation failure, or `null` if even the fallback is
  /// invalid (extremely defensive — should never happen in practice).
  ///
  /// Skips validation entirely when feature flags disable it or when the
  /// payload exceeds [ConnectionConstants.socketOutgoingContractValidationMaxBytes]
  /// (UTF-8 bytes), to keep CPU bounded for large result sets.
  dynamic validateOutgoing(dynamic payload) {
    if (!_featureFlags.enableSocketSchemaValidation) {
      return payload;
    }
    if (!_featureFlags.enableSocketOutgoingContractValidation) {
      return payload;
    }

    const softCap = ConnectionConstants.socketOutgoingContractValidationMaxBytes;
    if (softCap > 0 && _logSummarizer.exceedsByteBudget(payload, softCap)) {
      return payload;
    }

    final validation = payload is List<dynamic>
        ? _contractValidator.validateBatchResponse(payload)
        : _contractValidator.validateResponse(payload as Map<String, dynamic>);
    if (validation.isSuccess()) {
      return payload;
    }

    final failure = validation.exceptionOrNull()! as domain.Failure;
    AppLogger.error(
      'Outgoing rpc:response payload is invalid: ${failure.message}',
    );
    final fallback = prepareForSend(
      buildErrorResponse(
        id: null,
        code: RpcErrorCode.internalError,
        technicalMessage: 'Outgoing rpc:response failed contract validation',
      ),
    );

    final fallbackValidation = _contractValidator.validateResponse(fallback);
    if (fallbackValidation.isError()) {
      final fallbackFailure = fallbackValidation.exceptionOrNull()! as domain.Failure;
      AppLogger.error(
        'Fallback rpc:response payload is invalid: ${fallbackFailure.message}',
      );
      return null;
    }
    return fallback;
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

  /// Verifies the optional HMAC signature attached to an inbound JSON-only
  /// payload (legacy non-binary transport). Returns `true` when signing is
  /// disabled, when there is no signature, or when verification succeeds.
  bool verifyIncomingSignature(Map<String, dynamic> payload) {
    if (!_featureFlags.enablePayloadSigning || _payloadSigner == null) {
      return true;
    }
    final sigJson = payload['signature'] as Map<String, dynamic>?;
    if (sigJson == null) return true;
    final signature = PayloadSignature.fromJson(sigJson);
    return _payloadSigner.verify(payload, signature);
  }
}
