import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/protocol/rpc_wire_ack_id.dart';
import 'package:plug_agente/domain/protocol/transport_extension_negotiation.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/services/i_agent_health_status_provider.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/agent_latency_trace.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_batch_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_health_piggyback_sampler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_ack_coalescer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_concurrency_slots.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_rate_limit_responder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_request_context.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_response_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_validation_responder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_wire_payload.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_guard_mapping.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_response_enricher.dart';
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
    IAgentHealthStatusProvider? healthService,
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
       _hasReceivedCapabilities = hasReceivedCapabilities,
       _setHubSqlDashboardCapturePaused = setHubSqlDashboardCapturePaused {
    _healthPiggybackSampler = healthService == null
        ? null
        : RpcHealthPiggybackSampler(
            healthService: healthService,
            negotiationProvider: () =>
                TransportExtensionNegotiation.parseHealthPiggyback(
                  protocolProvider().negotiatedExtensions,
                ) ??
                const HealthPiggybackNegotiation(
                  intervalRequests: TransportExtensionNegotiation.defaultHealthPiggybackIntervalRequests,
                  freshnessThresholdMs: TransportExtensionNegotiation.defaultHealthPiggybackFreshnessThresholdMs,
                ),
          );
    _responseEnricher = RpcInboundResponseEnricher(
      healthPiggybackSampler: _healthPiggybackSampler,
    );

    final emitRpcResponseWithContext =
        emitRpcResponseWithMethodContext ??
        ((dynamic responseData, {Map<Object?, String> methodsById = const <Object?, String>{}}) {
          return emitRpcResponse(responseData);
        });

    _concurrencySlots = RpcInboundConcurrencySlots();
    _responseEmitter = RpcInboundResponseEmitter(
      concurrencySlots: _concurrencySlots,
      emitRpcResponse: emitRpcResponseWithContext,
      metricsCollector: metricsCollector,
    );
    _ackCoalescer = RpcInboundAckCoalescer(emitEvent: emitEvent);
    _rateLimitResponder = RpcInboundRateLimitResponder(
      frameCodec: _frameCodec,
      responsePreparer: _responsePreparer,
      responseEmitter: _responseEmitter,
    );
    _schemaValidationPipeline = RpcInboundSchemaValidationPipeline(
      jsonSchemaValidator: jsonSchemaValidator,
      logSummarizer: _logSummarizer,
      schemaCatalog: schemaCatalog,
    );
    _validationResponder = RpcInboundValidationResponder(
      schemaValidationPipeline: _schemaValidationPipeline,
      responsePreparer: _responsePreparer,
      responseEmitter: _responseEmitter,
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
      emitInboundRpcResponse: _responseEmitter.emit,
      emitEvent: emitEvent,
      sendSchemaValidationError: _validationResponder.sendSchemaValidationError,
      validateBatchRequestJsonSchemasOrEmit: _validationResponder.validateBatchRequestJsonSchemasOrEmit,
      hasNullIdCompatibilityViolation: _hasNullIdCompatibilityViolation,
      metricsCollector: metricsCollector,
      setHubSqlDashboardCapturePaused: _setHubSqlDashboardCapturePaused,
      responseEnricher: _responseEnricher,
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
  final bool Function() _hasReceivedCapabilities;
  final void Function(bool paused)? _setHubSqlDashboardCapturePaused;
  late final RpcHealthPiggybackSampler? _healthPiggybackSampler;
  late final RpcInboundResponseEnricher _responseEnricher;

  late final RpcInboundConcurrencySlots _concurrencySlots;
  late final RpcInboundResponseEmitter _responseEmitter;
  late final RpcInboundAckCoalescer _ackCoalescer;
  late final RpcInboundRateLimitResponder _rateLimitResponder;
  late final RpcInboundSchemaValidationPipeline _schemaValidationPipeline;
  late final RpcInboundValidationResponder _validationResponder;
  late final RpcBatchInboundHandler _batchHandler;

  /// Returns `true` if a slot was acquired (caller must call [releaseSlot]
  /// after dispatch completes, before outbound encode/emit). Returns `false`
  /// when the per-socket concurrency cap is reached; callers should answer with
  /// [emitConcurrencyLimitedError] and skip dispatching.
  bool tryAcquireSlot() => _concurrencySlots.tryAcquireSlot();

  void releaseSlot() => _concurrencySlots.releaseSlot();

  Future<void> handleRequestWithRelease(dynamic data) {
    return _concurrencySlots.runWithDeferredSlotRelease(() => handleRequest(data));
  }

  /// Builds and emits a `rateLimited` error response for a request that was
  /// rejected due to the concurrent-handler cap. Best effort decoding so we
  /// can still echo the original request id whenever possible.
  Future<void> emitConcurrencyLimitedError(dynamic rawData) {
    return _rateLimitResponder.emitConcurrencyLimitedError(rawData);
  }

  /// Processes a single inbound `rpc:request`. Acks are emitted as soon as the
  /// payload is parsed so the hub can release its in-flight slot quickly.
  Future<void> handleRequest(dynamic data) async {
    dynamic inboundRequestId;
    Object? inboundRequestMethod;
    try {
      final wirePayload = unwrapRpcInboundWirePayload(data);
      dynamic payload = wirePayload.payload;
      final socketAck = wirePayload.socketAck;

      // Protocol-not-ready guard: the hub must NOT send `rpc:request` before
      // receiving `agent:capabilities`. If it does, reject with a structured
      // error so the hub can retry after negotiation completes.
      if (!_hasReceivedCapabilities()) {
        await _validationResponder.sendSchemaValidationError(
          extractRequestIdFromRpcWirePayload(payload, frameCodec: _frameCodec),
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
        await _validationResponder.sendSchemaValidationError(
          extractRequestIdFromRpcWirePayload(payload, frameCodec: _frameCodec),
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
        await _validationResponder.sendSchemaValidationError(
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
      if (rpcInboundExceedsPayloadLimit(
        requestMap,
        protocolProvider: _protocolProvider,
        logSummarizer: _logSummarizer,
      )) {
        await _validationResponder.sendSchemaValidationError(
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
            await _validationResponder.sendSchemaValidationError(
              requestMap['id'],
              rpcInboundValidationFailureCode(failure),
              failure.message,
              method: requestMap['method'],
            );
            socketAck?.call();
            return;
          }
        }
        if (!await _validationResponder.validateSingleRequestJsonSchemasOrEmit(requestMap)) {
          socketAck?.call();
          return;
        }
      }

      if (!_responsePreparer.verifyIncomingSignature(requestMap)) {
        await _validationResponder.sendSchemaValidationError(
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
      final negotiatedExtensions = _protocolProvider().negotiatedExtensions;
      final latencyTrace =
          TransportExtensionNegotiation.isAgentPhaseTimingsNegotiated(negotiatedExtensions) &&
              (request.meta?.requestServerTimings ?? false)
          ? AgentLatencyTrace()
          : null;
      latencyTrace?.markFrameDecodeComplete();
      if (_hasNullIdCompatibilityViolation(requestMap)) {
        await _validationResponder.sendSchemaValidationError(
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
        final wireAckId = resolveRpcWireAckId(request);
        if (wireAckId != null) {
          _ackCoalescer.scheduleAck(wireAckId);
        }
      }
      socketAck?.call();
      latencyTrace?.markPreDispatchComplete();

      final guardResult = _requestGuard.evaluate(request);
      if (guardResult != RpcRequestGuardResult.allow) {
        final errorResponse = _responsePreparer.buildErrorResponse(
          id: request.id,
          code: rpcInboundGuardResultToCode(guardResult),
          technicalMessage: rpcInboundGuardResultToTechnicalMessage(guardResult),
          errorReason: rpcInboundGuardResultToReason(guardResult),
        );
        await _responseEmitter.emit(
          errorResponse,
          methodsById: <Object?, String>{request.id: request.method},
        );
        return;
      }

      final clientToken = extractClientTokenFromRpcParams(request.params);
      final protocol = _protocolProvider();
      final streamEmitter =
          rpcInboundShouldCreateStreamEmitter(
            request: request,
            negotiatedExtensions: protocol.negotiatedExtensions,
            featureFlags: _featureFlags,
          )
          ? _streamEmitterFactory()
          : null;
      final pauseDashboardCapture = rpcInboundShouldPauseDashboardCaptureForMethod(request.method);
      if (pauseDashboardCapture) {
        _setHubSqlDashboardCapturePaused?.call(true);
      }
      try {
        latencyTrace?.markDispatchStarted();
        final response = await _dispatcher.dispatch(
          request,
          _agentIdProvider(),
          clientToken: clientToken,
          streamEmitter: streamEmitter,
          limits: protocol.effectiveLimits,
          negotiatedExtensions: protocol.negotiatedExtensions,
        );
        latencyTrace?.markDispatchComplete(isSqlMethod: request.method.startsWith('sql.'));
        final tracedResponse = _responsePreparer.attachRequestTrace(request, response);
        final enrichedResponse = _responseEnricher.enrichUnaryResponse(
          request: request,
          response: tracedResponse,
          negotiatedExtensions: negotiatedExtensions,
          latencyTrace: latencyTrace,
        );
        _authorizationDecisionLogger.log(
          request: request,
          response: enrichedResponse,
          clientToken: clientToken,
        );

        if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
          return;
        }

        await _responseEmitter.emit(
          enrichedResponse,
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

      await _responseEmitter.emit(
        errorResponse,
        methodsById: rpcInboundMethodsByIdForValidationError(
          id: inboundRequestId,
          method: inboundRequestMethod,
        ),
      );
    }
  }

  /// Processes a JSON-RPC batch request via [RpcBatchInboundHandler].
  Future<void> handleBatchRequest(List<dynamic> data) {
    return _batchHandler.handleBatchRequest(data);
  }

  /// Cancels the ack-flush timer and discards any pending acks. Called by the
  /// transport client during socket close so a pending burst does not leak a
  /// `Timer` after disconnect; outstanding ids are dropped because the hub
  /// will observe the disconnection and re-dispatch on reconnect. The handler
  /// instance is reusable: a subsequent `rpc:request` rearms the buffer and
  /// timer transparently.
  void resetAckBuffer() {
    _ackCoalescer.resetAckBuffer();
    _healthPiggybackSampler?.reset();
  }

  bool _hasNullIdCompatibilityViolation(Map<String, dynamic> requestMap) {
    return rpcInboundHasNullIdCompatibilityViolation(
      requestMap,
      protocolProvider: _protocolProvider,
    );
  }
}
