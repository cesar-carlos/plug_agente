import 'dart:async';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_batch_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_guard_mapping.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_validation_error_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// Handles inbound `rpc:request` events (single and batch) from the hub.
///
/// Owns:
///   * Concurrency control (slot held through dispatch only; released before emit).
///   * Frame decode + per-payload validation (size limit, schema, signature).
///   * Replay/rate-limit guards via [RpcRequestGuard].
///   * `request_ack` / `batch_ack` delivery confirmations.
///   * Routing to [IRpcRequestDispatcher] (with optional streaming emitter).
///   * Trace context mirroring and authorization decision logging.
///
/// Stays free of `io.Socket`: the transport client passes in the emit/ack
/// callbacks. This makes the handler unit-testable in isolation and shrinks
/// the transport client to ~500 lines focused on socket lifecycle.
class RpcInboundHandler {
  RpcInboundHandler({
    required FeatureFlags featureFlags,
    required ProtocolConfig Function() protocolProvider,
    required String Function() agentIdProvider,
    required PayloadFrameCodec frameCodec,
    required PayloadLogSummarizer logSummarizer,
    required RpcResponsePreparer responsePreparer,
    required AuthorizationDecisionLogger authorizationDecisionLogger,
    required IRpcRequestDispatcher dispatcher,
    required RpcRequestGuard requestGuard,
    required RpcRequestSchemaValidator schemaValidator,
    required IRpcStreamEmitter Function() streamEmitterFactory,
    required Future<void> Function(dynamic responseData) emitRpcResponse,
    required Future<void> Function(String event, dynamic payload) emitEvent,
    required bool Function() hasReceivedCapabilities,
    Future<void> Function(
      dynamic responseData, {
      Map<Object?, String> methodsById,
    })?
    emitRpcResponseWithMethodContext,
    JsonSchemaContractValidator? jsonSchemaValidator,
    RpcMethodSchemaCatalog schemaCatalog = const RpcMethodSchemaCatalog(),
    MetricsCollector? metricsCollector,
  }) : _featureFlags = featureFlags,
       _protocolProvider = protocolProvider,
       _agentIdProvider = agentIdProvider,
       _frameCodec = frameCodec,
       _logSummarizer = logSummarizer,
       _responsePreparer = responsePreparer,
       _authorizationDecisionLogger = authorizationDecisionLogger,
       _dispatcher = dispatcher,
       _requestGuard = requestGuard,
       _schemaValidator = schemaValidator,
       _streamEmitterFactory = streamEmitterFactory,
       _emitRpcResponse =
           emitRpcResponseWithMethodContext ??
           ((dynamic responseData, {Map<Object?, String> methodsById = const <Object?, String>{}}) {
             return emitRpcResponse(responseData);
           }),
       _emitEvent = emitEvent,
       _hasReceivedCapabilities = hasReceivedCapabilities,
       _jsonSchemaValidator = jsonSchemaValidator,
       _schemaCatalog = schemaCatalog,
       _metricsCollector = metricsCollector {
    _batchHandler = RpcBatchInboundHandler(
      featureFlags: _featureFlags,
      protocolProvider: _protocolProvider,
      logSummarizer: _logSummarizer,
      responsePreparer: _responsePreparer,
      authorizationDecisionLogger: _authorizationDecisionLogger,
      dispatcher: _dispatcher,
      requestGuard: _requestGuard,
      schemaValidator: _schemaValidator,
      agentIdProvider: _agentIdProvider,
      emitInboundRpcResponse: _emitInboundRpcResponse,
      emitEvent: _emitEvent,
      sendSchemaValidationError: _sendSchemaValidationError,
      validateBatchRequestJsonSchemasOrEmit: _validateBatchRequestJsonSchemasOrEmit,
      hasNullIdCompatibilityViolation: _hasNullIdCompatibilityViolation,
      metricsCollector: _metricsCollector,
    );
  }

  final FeatureFlags _featureFlags;
  final ProtocolConfig Function() _protocolProvider;
  final String Function() _agentIdProvider;
  final PayloadFrameCodec _frameCodec;
  final PayloadLogSummarizer _logSummarizer;
  final RpcResponsePreparer _responsePreparer;
  final AuthorizationDecisionLogger _authorizationDecisionLogger;
  final IRpcRequestDispatcher _dispatcher;
  final RpcRequestGuard _requestGuard;
  final RpcRequestSchemaValidator _schemaValidator;
  final IRpcStreamEmitter Function() _streamEmitterFactory;
  final Future<void> Function(
    dynamic responseData, {
    Map<Object?, String> methodsById,
  })
  _emitRpcResponse;
  final Future<void> Function(String event, dynamic payload) _emitEvent;
  final bool Function() _hasReceivedCapabilities;
  final JsonSchemaContractValidator? _jsonSchemaValidator;
  final RpcMethodSchemaCatalog _schemaCatalog;
  final MetricsCollector? _metricsCollector;

  late final RpcBatchInboundHandler _batchHandler;

  int _activeRpcHandlers = 0;
  bool _deferInboundSlotRelease = false;

  /// Returns `true` if a slot was acquired (caller must call [releaseSlot]
  /// after dispatch completes, before outbound encode/emit). Returns `false`
  /// when the per-socket concurrency cap is reached; callers should answer with
  /// [emitConcurrencyLimitedError] and skip dispatching.
  bool tryAcquireSlot() {
    if (_activeRpcHandlers >= ConnectionConstants.maxConcurrentRpcHandlers) {
      return false;
    }
    _activeRpcHandlers++;
    return true;
  }

  void releaseSlot() {
    _activeRpcHandlers--;
  }

  void _releaseInboundSlotIfDeferred() {
    if (!_deferInboundSlotRelease) {
      return;
    }
    _deferInboundSlotRelease = false;
    releaseSlot();
  }

  Future<void> _emitInboundRpcResponse(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) async {
    _releaseInboundSlotIfDeferred();
    await _emitRpcResponse(
      responseData,
      methodsById: methodsById,
    );
  }

  _WirePayloadWithAck _unwrapWirePayload(dynamic data) {
    if (data is List && data.length == 2 && data[1] is Function) {
      return _WirePayloadWithAck(
        payload: data[0],
        socketAck: data[1] as void Function(),
      );
    }
    return _WirePayloadWithAck(payload: data);
  }

  Future<void> handleRequestWithRelease(dynamic data) async {
    _deferInboundSlotRelease = true;
    try {
      await handleRequest(data);
    } finally {
      _releaseInboundSlotIfDeferred();
    }
  }

  /// Builds and emits a `rateLimited` error response for a request that was
  /// rejected due to the concurrent-handler cap. Best effort decoding so we
  /// can still echo the original request id whenever possible.
  Future<void> emitConcurrencyLimitedError(dynamic rawData) async {
    final wirePayload = _unwrapWirePayload(rawData);
    final payload = wirePayload.payload;
    dynamic id;
    if (payload is Map<String, dynamic> && _frameCodec.looksLikePayloadFrame(payload)) {
      final decodeResult = _frameCodec.decodeIncoming(payload, sourceEvent: 'rpc:request');
      decodeResult.fold(
        (dynamic decodedPayload) {
          if (decodedPayload is Map<String, dynamic>) {
            id = decodedPayload['id'];
          }
        },
        (_) => id = null,
      );
    } else if (payload is Map<String, dynamic>) {
      id = payload['id'];
    }

    try {
      await _emitRpcResponse(
        _responsePreparer.buildErrorResponse(
          id: id,
          code: RpcErrorCode.rateLimited,
          technicalMessage: RpcInboundConstants.concurrentHandlersExceededTechnicalMessage(
            ConnectionConstants.maxConcurrentRpcHandlers,
          ),
          // Distinguish from window-based rate limiting so the hub knows whether
          // to back off in time (see rateWindowExceededReason) or reduce parallelism
          // (see concurrentHandlersExceededReason).
          errorReason: RpcInboundConstants.concurrentHandlersExceededReason,
        ),
      );
    } finally {
      wirePayload.socketAck?.call();
    }
  }

  /// Processes a single inbound `rpc:request`. Acks are emitted as soon as the
  /// payload is parsed so the hub can release its in-flight slot quickly.
  Future<void> handleRequest(dynamic data) async {
    dynamic inboundRequestId;
    try {
      final wirePayload = _unwrapWirePayload(data);
      dynamic payload = wirePayload.payload;
      final socketAck = wirePayload.socketAck;

      // Protocol-not-ready guard: the hub must NOT send `rpc:request` before
      // receiving `agent:capabilities`. If it does, reject with a structured
      // error so the hub can retry after negotiation completes.
      if (!_hasReceivedCapabilities()) {
        await _sendSchemaValidationError(
          _extractRequestIdFromWirePayload(payload),
          RpcErrorCode.invalidRequest,
          RpcInboundConstants.protocolNotReadyTechnicalMessage,
          errorReason: RpcInboundConstants.protocolNotReadyReason,
        );
        socketAck?.call();
        return;
      }

      final decodeResult = await _frameCodec.decodeIncomingAsync(payload, sourceEvent: 'rpc:request');
      if (decodeResult.isError()) {
        final failure = decodeResult.exceptionOrNull()! as domain.Failure;
        final mapped = mapRpcInboundTransportDecodeFailure(failure);
        await _sendSchemaValidationError(
          _extractRequestIdFromWirePayload(payload),
          mapped.code,
          failure.message,
          errorReason: mapped.reason,
        );
        socketAck?.call();
        return;
      }
      payload = decodeResult.getOrThrow();

      if (payload is List) {
        await handleBatchRequest(payload);
        socketAck?.call();
        return;
      }

      if (payload is! Map<String, dynamic>) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidRequest,
          RpcInboundConstants.requestMustBeJsonObjectTechnicalMessage,
        );
        socketAck?.call();
        return;
      }

      final requestMap = payload;
      inboundRequestId = requestMap['id'];
      if (_exceedsPayloadLimit(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.invalidPayload,
          RpcInboundConstants.requestExceedsPayloadLimitTechnicalMessage,
        );
        socketAck?.call();
        return;
      }

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateSingle(
          requestMap,
          limits: _protocolProvider().effectiveLimits,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              requestMap['id'],
              rpcInboundValidationFailureCode(failure),
              failure.message,
            );
            socketAck?.call();
            return;
          }
        }
        if (!await _validateSingleRequestJsonSchemasOrEmit(requestMap)) {
          socketAck?.call();
          return;
        }
      }

      if (!_responsePreparer.verifyIncomingSignature(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.authenticationFailed,
          RpcInboundConstants.invalidPayloadSignatureTechnicalMessage,
          errorReason: RpcErrorCode.reasonInvalidSignature,
        );
        socketAck?.call();
        return;
      }

      final request = RpcRequest.fromJson(requestMap);
      if (_hasNullIdCompatibilityViolation(requestMap)) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidRequest,
          RpcInboundConstants.nullIdNotificationsCompatibilityTechnicalMessage,
        );
        socketAck?.call();
        return;
      }

      if (_featureFlags.enableSocketDeliveryGuarantees && !request.isNotification) {
        await _emitRequestAck(request.id);
      }
      socketAck?.call();

      final guardResult = _requestGuard.evaluate(request);
      if (guardResult != RpcRequestGuardResult.allow) {
        final errorResponse = _responsePreparer.buildErrorResponse(
          id: request.id,
          code: rpcInboundGuardResultToCode(guardResult),
          technicalMessage: rpcInboundGuardResultToTechnicalMessage(guardResult),
          errorReason: rpcInboundGuardResultToReason(guardResult),
        );
        await _emitInboundRpcResponse(errorResponse);
        return;
      }

      final clientToken = _extractClientTokenFromRpcParams(request.params);
      final protocol = _protocolProvider();
      final streamEmitter =
          _shouldCreateStreamEmitter(
            request: request,
            negotiatedExtensions: protocol.negotiatedExtensions,
          )
          ? _streamEmitterFactory()
          : null;
      final response = await _dispatcher.dispatch(
        request,
        _agentIdProvider(),
        clientToken: clientToken,
        streamEmitter: streamEmitter,
        limits: protocol.effectiveLimits,
        negotiatedExtensions: protocol.negotiatedExtensions,
      );
      final tracedResponse = _responsePreparer.attachRequestTrace(request, response);
      _authorizationDecisionLogger.log(
        request: request,
        response: tracedResponse,
        clientToken: clientToken,
      );

      if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
        return;
      }

      await _emitInboundRpcResponse(
        tracedResponse,
        methodsById: <Object?, String>{request.id: request.method},
      );
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC request',
        error,
        stackTrace,
      );

      // Use internalError (-32603) here. parseError (-32700) is reserved for
      // failures of jsonDecode itself, which happen inside the PayloadFrameCodec
      // and are already mapped to invalidPayload/decodingFailed.
      // The error.toString() is intentionally not echoed in technical_message
      // because it can leak internal stack traces or sensitive payload data;
      // the correlation id lets operators link this response to the log entry.
      final errorResponse = RpcResponse.error(
        id: inboundRequestId,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.internalError,
            technicalMessage: RpcInboundConstants.unhandledSingleRequestTechnicalMessage,
            extra: {
              'failure_code': RpcInboundConstants.unhandledExceptionFailureCode,
              'exception_type': error.runtimeType.toString(),
            },
          ),
        ),
      );

      await _emitInboundRpcResponse(errorResponse);
    }
  }

  bool _shouldCreateStreamEmitter({
    required RpcRequest request,
    required Map<String, dynamic> negotiatedExtensions,
  }) {
    if (request.isNotification) {
      return false;
    }
    final negotiatedStreaming = negotiatedExtensions['streamingResults'] as bool? ?? false;
    return negotiatedStreaming &&
        (_featureFlags.enableSocketStreamingChunks || _featureFlags.enableSocketStreamingFromDb);
  }

  /// Processes a JSON-RPC batch request via [RpcBatchInboundHandler].
  Future<void> handleBatchRequest(List<dynamic> data) {
    return _batchHandler.handleBatchRequest(data);
  }

  Future<void> _emitRequestAck(dynamic requestId) async {
    if (requestId == null) return;
    final ackPayload = {
      'request_id': requestId.toString(),
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEvent('rpc:request_ack', ackPayload);
  }

  Future<bool> _validateBatchRequestJsonSchemasOrEmit(List<dynamic> data) async {
    final jsonSchemaValidator = _jsonSchemaValidator;
    if (jsonSchemaValidator == null) {
      return true;
    }

    final batchValidation = jsonSchemaValidator.validate(
      schemaId: TransportSchemaIds.rpcBatchRequest,
      payload: data,
      direction: 'inbound',
    );
    if (batchValidation.isError()) {
      final failure = batchValidation.exceptionOrNull()! as domain.Failure;
      await _sendSchemaValidationError(
        null,
        RpcErrorCode.invalidRequest,
        failure.message,
      );
      return false;
    }

    for (final item in data.whereType<Map<String, dynamic>>()) {
      if (!await _validateSingleRequestJsonSchemasOrEmit(item)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _validateSingleRequestJsonSchemasOrEmit(Map<String, dynamic> requestMap) async {
    final envelopeFailure = _validateRequestEnvelopeJsonSchema(requestMap);
    if (envelopeFailure != null) {
      await _sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidRequest,
        envelopeFailure.message,
      );
      return false;
    }

    final paramsFailure = _validateRequestParamsJsonSchema(requestMap);
    if (paramsFailure != null) {
      await _sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidParams,
        paramsFailure.message,
      );
      return false;
    }

    return true;
  }

  domain.Failure? _validateRequestEnvelopeJsonSchema(Map<String, dynamic> requestMap) {
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

  domain.Failure? _validateRequestParamsJsonSchema(Map<String, dynamic> requestMap) {
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

  Future<void> _sendSchemaValidationError(
    dynamic id,
    int code,
    String technicalMessage, {
    String? errorReason,
  }) async {
    final errorResponse = _responsePreparer.buildErrorResponse(
      id: id,
      code: code,
      technicalMessage: technicalMessage,
      errorReason: errorReason,
    );
    await _emitInboundRpcResponse(errorResponse);
  }

  bool _exceedsPayloadLimit(dynamic payload) {
    final limit = _protocolProvider().effectiveLimits.maxDecodedPayloadBytes;
    return _logSummarizer.exceedsByteBudget(payload, limit);
  }

  bool _hasNullIdCompatibilityViolation(Map<String, dynamic> requestMap) {
    return requestMap.containsKey('id') && requestMap['id'] == null && !_allowsNullIdNotifications();
  }

  bool _allowsNullIdNotifications() {
    final extensionValue = _protocolProvider().negotiatedExtensions['notificationNullIdCompatibility'];
    if (extensionValue is bool) return extensionValue;
    return true;
  }

  dynamic _extractRequestIdFromWirePayload(dynamic payload) {
    if (_frameCodec.looksLikePayloadFrame(payload)) {
      return (payload as Map<String, dynamic>)['requestId'];
    }
    if (payload is Map<String, dynamic>) {
      return payload['id'] ?? payload['request_id'];
    }
    return null;
  }

  String? _extractClientTokenFromRpcParams(dynamic params) {
    if (params is! Map<String, dynamic>) return null;
    final raw = params['client_token'] as String? ?? params['auth'] as String? ?? params['clientToken'] as String?;
    return raw != null && raw.trim().isNotEmpty ? raw.trim() : null;
  }
}

class _WirePayloadWithAck {
  const _WirePayloadWithAck({
    required this.payload,
    this.socketAck,
  });

  final dynamic payload;
  final void Function()? socketAck;
}
