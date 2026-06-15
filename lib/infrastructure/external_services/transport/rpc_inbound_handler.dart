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
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_schema_validation_pipeline.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_validation_error_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

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
    void Function(bool paused)? setHubSqlDashboardCapturePaused,
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
       _metricsCollector = metricsCollector,
       _setHubSqlDashboardCapturePaused = setHubSqlDashboardCapturePaused {
    _schemaValidationPipeline = RpcInboundSchemaValidationPipeline(
      jsonSchemaValidator: _jsonSchemaValidator,
      logSummarizer: _logSummarizer,
      schemaCatalog: _schemaCatalog,
    );
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
      setHubSqlDashboardCapturePaused: _setHubSqlDashboardCapturePaused,
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
  final void Function(bool paused)? _setHubSqlDashboardCapturePaused;

  late final RpcInboundSchemaValidationPipeline _schemaValidationPipeline;
  late final RpcBatchInboundHandler _batchHandler;

  int _activeRpcHandlers = 0;

  // Coalescing buffer for inbound `rpc:request_ack` emission. Bursts of
  // `rpc:request` (e.g. cross-agent `mergeAll`) are merged into a single
  // `rpc:batch_ack` to reduce socket emit overhead. The hub already accepts
  // both forms; see `plug_server/docs/plug_agente/03_performance_roadmap.md`
  // item 3.
  final List<String> _pendingAckIds = <String>[];
  Timer? _ackFlushTimer;
  // Per-call slot-release state, set when [handleRequestWithRelease] runs and
  // looked up via [Zone.current] inside [_emitInboundRpcResponse]. Using an
  // instance bool would race across concurrent inbound requests: the first
  // call to finish would read the second call's `true` and release its slot,
  // leaving the second call's slot orphaned for the lifetime of the socket.
  static const _slotReleaseZoneKey = #rpcInboundHandlerSlotRelease;

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
    if (_activeRpcHandlers > 0) {
      _activeRpcHandlers--;
    }
  }

  void _releaseInboundSlotIfDeferred() {
    final state = Zone.current[_slotReleaseZoneKey];
    if (state is! _SlotReleaseState || state.released) {
      return;
    }
    state.released = true;
    releaseSlot();
  }

  Future<void> _emitInboundRpcResponse(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) async {
    _releaseInboundSlotIfDeferred();
    // Hub sql.execute must not block the socket handler on outbound encode/emit.
    unawaited(
      _emitRpcResponse(
        responseData,
        methodsById: methodsById,
      ).catchError((Object error, StackTrace stackTrace) {
        _metricsCollector?.recordRpcResponseEmitFailure();
        AppLogger.error(
          'Failed to emit inbound rpc:response',
          error,
          stackTrace,
        );
      }),
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
    final state = _SlotReleaseState();
    return runZoned(
      () async {
        try {
          await handleRequest(data);
        } finally {
          _releaseInboundSlotIfDeferred();
        }
      },
      zoneValues: <Object, Object?>{_slotReleaseZoneKey: state},
    );
  }

  /// Builds and emits a `rateLimited` error response for a request that was
  /// rejected due to the concurrent-handler cap. Best effort decoding so we
  /// can still echo the original request id whenever possible.
  Future<void> emitConcurrencyLimitedError(dynamic rawData) async {
    final wirePayload = _unwrapWirePayload(rawData);
    try {
      final identity = _extractBestEffortRequestIdentityForRateLimit(wirePayload.payload);
      await _emitRpcResponse(
        _responsePreparer.buildErrorResponse(
          id: identity.id,
          code: RpcErrorCode.rateLimited,
          technicalMessage: RpcInboundConstants.concurrentHandlersExceededTechnicalMessage(
            ConnectionConstants.maxConcurrentRpcHandlers,
          ),
          // Distinguish from window-based rate limiting so the hub knows whether
          // to back off in time (see rateWindowExceededReason) or reduce parallelism
          // (see concurrentHandlersExceededReason).
          errorReason: RpcInboundConstants.concurrentHandlersExceededReason,
        ),
        methodsById: _methodsByIdForValidationError(
          id: identity.id,
          method: identity.method,
        ),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to emit rate-limited rpc:response',
        error,
        stackTrace,
      );
    } finally {
      wirePayload.socketAck?.call();
    }
  }

  bool _shouldPauseDashboardCaptureForMethod(String method) {
    return method == 'sql.execute' || method == 'sql.executeBatch';
  }

  _BestEffortRequestIdentity _extractBestEffortRequestIdentityForRateLimit(dynamic payload) {
    try {
      if (payload is Map<String, dynamic> && _frameCodec.looksLikePayloadFrame(payload)) {
        final decodeResult = _frameCodec.decodeIncoming(payload, sourceEvent: 'rpc:request');
        if (decodeResult.isSuccess()) {
          final decodedPayload = decodeResult.getOrThrow();
          if (decodedPayload is Map<String, dynamic>) {
            return _BestEffortRequestIdentity(
              id: decodedPayload['id'],
              method: decodedPayload['method'],
            );
          }
        }
        return const _BestEffortRequestIdentity();
      }
      if (payload is Map<String, dynamic>) {
        return _BestEffortRequestIdentity(
          id: payload['id'],
          method: payload['method'],
        );
      }
      return const _BestEffortRequestIdentity();
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to extract request identity while building rate-limited response',
        error,
        stackTrace,
      );
      return const _BestEffortRequestIdentity();
    }
  }

  /// Processes a single inbound `rpc:request`. Acks are emitted as soon as the
  /// payload is parsed so the hub can release its in-flight slot quickly.
  Future<void> handleRequest(dynamic data) async {
    dynamic inboundRequestId;
    Object? inboundRequestMethod;
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
      inboundRequestMethod = requestMap['method'];
      if (_exceedsPayloadLimit(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.invalidPayload,
          RpcInboundConstants.requestExceedsPayloadLimitTechnicalMessage,
          method: requestMap['method'],
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
              method: requestMap['method'],
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
          method: requestMap['method'],
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
          method: requestMap['method'],
        );
        socketAck?.call();
        return;
      }

      if (_featureFlags.enableSocketDeliveryGuarantees && !request.isNotification) {
        // Ack means "accepted for processing", not "dispatch completed".
        // The hub may receive this before ODBC work finishes; see delivery guarantees doc.
        _scheduleAck(request.id);
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
        await _emitInboundRpcResponse(
          errorResponse,
          methodsById: <Object?, String>{request.id: request.method},
        );
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
      final pauseDashboardCapture = _shouldPauseDashboardCaptureForMethod(request.method);
      if (pauseDashboardCapture) {
        _setHubSqlDashboardCapturePaused?.call(true);
      }
      try {
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
      } finally {
        if (pauseDashboardCapture) {
          _setHubSqlDashboardCapturePaused?.call(false);
        }
      }
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

      await _emitInboundRpcResponse(
        errorResponse,
        methodsById: _methodsByIdForValidationError(
          id: inboundRequestId,
          method: inboundRequestMethod,
        ),
      );
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

  /// Buffers an inbound `rpc:request` ack and flushes either when the buffer
  /// reaches [ConnectionConstants.rpcAckCoalesceMaxBatch] or after
  /// [ConnectionConstants.rpcAckCoalesceFlushInterval] elapses, whichever
  /// happens first. A buffer of size 1 still emits the canonical
  /// `rpc:request_ack`, preserving the legacy single-id wire shape.
  void _scheduleAck(dynamic requestId) {
    if (requestId == null) return;
    _pendingAckIds.add(requestId.toString());
    if (_pendingAckIds.length >= ConnectionConstants.rpcAckCoalesceMaxBatch) {
      _ackFlushTimer?.cancel();
      _ackFlushTimer = null;
      unawaited(_flushPendingAcks());
      return;
    }
    _ackFlushTimer ??= Timer(ConnectionConstants.rpcAckCoalesceFlushInterval, () {
      _ackFlushTimer = null;
      unawaited(_flushPendingAcks());
    });
  }

  Future<void> _flushPendingAcks() async {
    if (_pendingAckIds.isEmpty) return;
    final ids = List<String>.unmodifiable(_pendingAckIds);
    _pendingAckIds.clear();
    final receivedAt = DateTime.now().toIso8601String();
    if (ids.length == 1) {
      await _emitEvent('rpc:request_ack', <String, dynamic>{
        'request_id': ids.first,
        'received_at': receivedAt,
      });
      return;
    }
    await _emitEvent('rpc:batch_ack', <String, dynamic>{
      'request_ids': ids,
      'received_at': receivedAt,
    });
  }

  /// Cancels the ack-flush timer and discards any pending acks. Called by the
  /// transport client during socket close so a pending burst does not leak a
  /// `Timer` after disconnect; outstanding ids are dropped because the hub
  /// will observe the disconnection and re-dispatch on reconnect. The handler
  /// instance is reusable: a subsequent `rpc:request` rearms the buffer and
  /// timer transparently.
  void resetAckBuffer() {
    _ackFlushTimer?.cancel();
    _ackFlushTimer = null;
    _pendingAckIds.clear();
  }

  Future<bool> _validateBatchRequestJsonSchemasOrEmit(List<dynamic> data) async {
    final batchFailure = _schemaValidationPipeline.validateBatchEnvelope(data);
    if (batchFailure != null) {
      final firstId = data.whereType<Map<String, dynamic>>().firstOrNull?['id'];
      await _sendSchemaValidationError(
        firstId,
        RpcErrorCode.invalidRequest,
        batchFailure.message,
        method: data.whereType<Map<String, dynamic>>().firstOrNull?['method'],
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
    if (_schemaValidationPipeline.shouldSkipLargePayload(requestMap)) {
      _schemaValidationPipeline.recordSkippedLargePayload();
      final criticalFailure = _schemaValidationPipeline.validateCriticalFieldsWhenSkipping(requestMap);
      if (criticalFailure != null) {
        await _sendSchemaValidationError(
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
      await _sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidRequest,
        envelopeFailure.message,
        method: requestMap['method'],
      );
      return false;
    }

    final paramsFailure = _schemaValidationPipeline.validateRequestParams(requestMap);
    if (paramsFailure != null) {
      await _sendSchemaValidationError(
        requestMap['id'],
        RpcErrorCode.invalidParams,
        paramsFailure.message,
        method: requestMap['method'],
      );
      return false;
    }

    return true;
  }

  Future<void> _sendSchemaValidationError(
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
    await _emitInboundRpcResponse(
      errorResponse,
      methodsById: _methodsByIdForValidationError(
        id: id,
        method: method,
      ),
    );
  }

  Map<Object?, String> _methodsByIdForValidationError({
    required dynamic id,
    required Object? method,
  }) {
    if (method is String && _shouldPauseDashboardCaptureForMethod(method)) {
      return <Object?, String>{id: method};
    }
    return const <Object?, String>{};
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

class _BestEffortRequestIdentity {
  const _BestEffortRequestIdentity({
    this.id,
    this.method,
  });

  final dynamic id;
  final Object? method;
}

/// Per-call slot-release flag carried in a Zone so concurrent invocations of
/// [RpcInboundHandler.handleRequestWithRelease] do not stomp on each other.
class _SlotReleaseState {
  bool released = false;
}
