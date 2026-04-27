import 'dart:async';

import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

/// Handles inbound `rpc:request` events (single and batch) from the hub.
///
/// Owns:
///   * Concurrency control (slot acquire/release before dispatch).
///   * Frame decode + per-payload validation (size limit, schema, signature).
///   * Replay/rate-limit guards via [RpcRequestGuard].
///   * `request_ack` / `batch_ack` delivery confirmations.
///   * Routing to [RpcMethodDispatcher] (with optional streaming emitter).
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
    required OpenRpcDocumentLoader openRpcDocumentLoader,
    required RpcMethodDispatcher dispatcher,
    required RpcRequestGuard requestGuard,
    required RpcRequestSchemaValidator schemaValidator,
    required IRpcStreamEmitter Function() streamEmitterFactory,
    required Future<void> Function(dynamic responseData) emitRpcResponse,
    required Future<void> Function(String event, dynamic payload) emitEvent,
    required bool Function() hasReceivedCapabilities,
  }) : _featureFlags = featureFlags,
       _protocolProvider = protocolProvider,
       _agentIdProvider = agentIdProvider,
       _frameCodec = frameCodec,
       _logSummarizer = logSummarizer,
       _responsePreparer = responsePreparer,
       _authorizationDecisionLogger = authorizationDecisionLogger,
       _openRpcDocumentLoader = openRpcDocumentLoader,
       _dispatcher = dispatcher,
       _requestGuard = requestGuard,
       _schemaValidator = schemaValidator,
       _streamEmitterFactory = streamEmitterFactory,
       _emitRpcResponse = emitRpcResponse,
       _emitEvent = emitEvent,
       _hasReceivedCapabilities = hasReceivedCapabilities;

  final FeatureFlags _featureFlags;
  final ProtocolConfig Function() _protocolProvider;
  final String Function() _agentIdProvider;
  final PayloadFrameCodec _frameCodec;
  final PayloadLogSummarizer _logSummarizer;
  final RpcResponsePreparer _responsePreparer;
  final AuthorizationDecisionLogger _authorizationDecisionLogger;
  final OpenRpcDocumentLoader _openRpcDocumentLoader;
  final RpcMethodDispatcher _dispatcher;
  final RpcRequestGuard _requestGuard;
  final RpcRequestSchemaValidator _schemaValidator;
  final IRpcStreamEmitter Function() _streamEmitterFactory;
  final Future<void> Function(dynamic responseData) _emitRpcResponse;
  final Future<void> Function(String event, dynamic payload) _emitEvent;
  final bool Function() _hasReceivedCapabilities;

  int _activeRpcHandlers = 0;

  /// Returns `true` if a slot was acquired (caller must call [releaseSlot]
  /// after the request handler completes). Returns `false` when the per-socket
  /// concurrency cap is reached; callers should answer with
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

  Future<void> handleRequestWithRelease(dynamic data) async {
    try {
      await handleRequest(data);
    } finally {
      releaseSlot();
    }
  }

  /// Builds and emits a `rateLimited` error response for a request that was
  /// rejected due to the concurrent-handler cap. Best effort decoding so we
  /// can still echo the original request id whenever possible.
  Future<void> emitConcurrencyLimitedError(dynamic rawData) async {
    dynamic id;
    try {
      if (rawData is Map<String, dynamic> && _frameCodec.looksLikePayloadFrame(rawData)) {
        final payload = _frameCodec.decodeIncoming(rawData, sourceEvent: 'rpc:request');
        if (payload is Map<String, dynamic>) {
          id = payload['id'];
        }
      } else if (rawData is Map<String, dynamic>) {
        id = rawData['id'];
      }
    } on Object {
      id = null;
    }

    await _emitRpcResponse(
      _responsePreparer.buildErrorResponse(
        id: id,
        code: RpcErrorCode.rateLimited,
        technicalMessage:
            'Concurrent RPC handler limit exceeded '
            '(${ConnectionConstants.maxConcurrentRpcHandlers})',
        // Distinguish from window-based rate limiting so the hub knows whether
        // to back off in time (rate_window_exceeded) or reduce parallelism
        // (concurrent_handlers_exceeded).
        errorReason: 'concurrent_handlers_exceeded',
      ),
    );
  }

  /// Processes a single inbound `rpc:request`. Acks are emitted as soon as the
  /// payload is parsed so the hub can release its in-flight slot quickly.
  Future<void> handleRequest(dynamic data) async {
    try {
      dynamic payload = data;
      void Function()? socketAck;

      if (data is List && data.length == 2 && data[1] is Function) {
        payload = data[0];
        socketAck = data[1] as void Function();
      }

      // Protocol-not-ready guard: the hub must NOT send `rpc:request` before
      // receiving `agent:capabilities`. If it does, reject with a structured
      // error so the hub can retry after negotiation completes.
      if (!_hasReceivedCapabilities()) {
        await _sendSchemaValidationError(
          _extractRequestIdFromWirePayload(payload),
          RpcErrorCode.invalidRequest,
          'Protocol not ready: agent:capabilities has not been received yet',
          errorReason: 'protocol_not_ready',
        );
        socketAck?.call();
        return;
      }

      try {
        payload = await _frameCodec.decodeIncomingAsync(payload, sourceEvent: 'rpc:request');
      } on domain.Failure catch (failure) {
        final mapped = _mapInboundTransportDecodeFailure(failure);
        await _sendSchemaValidationError(
          _extractRequestIdFromWirePayload(payload),
          mapped.code,
          failure.message,
          errorReason: mapped.reason,
        );
        socketAck?.call();
        return;
      }

      if (payload is List) {
        await handleBatchRequest(payload);
        socketAck?.call();
        return;
      }

      if (payload is! Map<String, dynamic>) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidRequest,
          'Request must be a JSON object',
        );
        socketAck?.call();
        return;
      }

      final requestMap = payload;
      if (_exceedsPayloadLimit(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.invalidPayload,
          'Request exceeds negotiated payload limit',
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
              _validationFailureCode(failure),
              failure.message,
            );
            socketAck?.call();
            return;
          }
        }
      }

      if (!_responsePreparer.verifyIncomingSignature(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.authenticationFailed,
          'Invalid payload signature',
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
          'id: null notifications require negotiated compatibility',
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
          code: _guardResultToCode(guardResult),
          technicalMessage: _guardResultToTechnicalMessage(guardResult),
          errorReason: _guardResultToReason(guardResult),
        );
        await _emitRpcResponse(errorResponse);
        return;
      }

      if (request.method == 'rpc.discover') {
        if (!_featureFlags.enableSocketNotificationsContract || !request.isNotification) {
          final doc = await _openRpcDocumentLoader.getDocument();
          final response = _responsePreparer.attachRequestTrace(
            request,
            RpcResponse.success(id: request.id, result: doc),
          );
          await _emitRpcResponse(response);
        }
        return;
      }

      final clientToken = _extractClientTokenFromRpcParams(request.params);
      final streamEmitter = !request.isNotification && _featureFlags.enableSocketStreamingChunks
          ? _streamEmitterFactory()
          : null;
      final response = await _dispatcher.dispatch(
        request,
        _agentIdProvider(),
        clientToken: clientToken,
        streamEmitter: streamEmitter,
        limits: _protocolProvider().effectiveLimits,
        negotiatedExtensions: _protocolProvider().negotiatedExtensions,
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

      await _emitRpcResponse(tracedResponse);
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
        id: null,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.internalError,
            technicalMessage: 'Unhandled exception in RPC request handler',
            extra: {
              'failure_code': 'unhandled_exception',
              'exception_type': error.runtimeType.toString(),
            },
          ),
        ),
      );

      await _emitRpcResponse(errorResponse);
    }
  }

  /// Processes a JSON-RPC batch request. Validates the envelope, dispatches
  /// each item independently, then emits the merged batch response (optionally
  /// preserving order based on the negotiated extension).
  Future<void> handleBatchRequest(List<dynamic> data) async {
    try {
      if (data.isEmpty) {
        const code = RpcErrorCode.invalidRequest;
        final errorResponse = RpcResponse.error(
          id: null,
          error: RpcError(
            code: code,
            message: RpcErrorCode.getMessage(code),
            data: RpcErrorCode.buildErrorData(
              code: code,
              technicalMessage: 'Batch request cannot be empty',
              extra: {'detail': 'Batch request cannot be empty'},
            ),
          ),
        );
        await _emitRpcResponse(errorResponse);
        return;
      }

      if (_exceedsPayloadLimit(data)) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidPayload,
          'Batch request exceeds negotiated payload limit',
        );
        return;
      }

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateBatch(
          data,
          limits: _protocolProvider().effectiveLimits,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              null,
              _validationFailureCode(failure),
              failure.message,
            );
            return;
          }
        }
      }

      for (final item in data) {
        if (item is! Map<String, dynamic>) {
          await _sendSchemaValidationError(
            null,
            RpcErrorCode.invalidRequest,
            'Each element in a batch must be a JSON object',
          );
          return;
        }
        if (!_responsePreparer.verifyIncomingSignature(item)) {
          await _sendSchemaValidationError(
            item['id'],
            RpcErrorCode.authenticationFailed,
            'Invalid payload signature',
            errorReason: RpcErrorCode.reasonInvalidSignature,
          );
          return;
        }
      }

      final requests = data.map((e) => RpcRequest.fromJson(e as Map<String, dynamic>)).toList();

      for (final item in data.whereType<Map<String, dynamic>>()) {
        if (_hasNullIdCompatibilityViolation(item)) {
          await _sendSchemaValidationError(
            null,
            RpcErrorCode.invalidRequest,
            'id: null notifications require negotiated compatibility',
          );
          return;
        }
      }

      if (_featureFlags.enableSocketDeliveryGuarantees) {
        await _emitBatchRequestAck(requests);
      }

      if (_featureFlags.enableSocketBatchStrictValidation) {
        final batch = RpcBatchRequest(requests);
        final validation = batch.validateStrict(
          maxSize: _protocolProvider().effectiveLimits.maxBatchSize,
        );
        switch (validation) {
          case RpcBatchDuplicateIds(:final duplicateIds):
            await _emitRpcResponse(
              RpcResponse.error(
                id: null,
                error: RpcError(
                  code: RpcErrorCode.invalidRequest,
                  message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                  data: RpcErrorCode.buildErrorData(
                    code: RpcErrorCode.invalidRequest,
                    technicalMessage: 'Batch contains duplicate request IDs: $duplicateIds',
                    reason: 'batch_duplicate_ids',
                    extra: {'duplicate_ids': duplicateIds},
                  ),
                ),
              ),
            );
            return;
          case RpcBatchExceedsLimit(:final size, :final limit):
            await _emitRpcResponse(
              RpcResponse.error(
                id: null,
                error: RpcError(
                  code: RpcErrorCode.invalidRequest,
                  message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                  data: RpcErrorCode.buildErrorData(
                    code: RpcErrorCode.invalidRequest,
                    technicalMessage: 'Batch exceeds limit: $size > $limit',
                    reason: 'batch_exceeds_limit',
                    extra: {'size': size, 'limit': limit},
                  ),
                ),
              ),
            );
            return;
          case RpcBatchValid():
            break;
        }
      }

      final responses = <({int index, RpcResponse response})>[];

      for (var index = 0; index < requests.length; index++) {
        final request = requests[index];
        final guardResult = _requestGuard.evaluate(request);
        if (guardResult != RpcRequestGuardResult.allow) {
          final errorResponse = _responsePreparer.buildErrorResponse(
            id: request.id,
            code: _guardResultToCode(guardResult),
            technicalMessage: _guardResultToTechnicalMessage(guardResult),
            errorReason: _guardResultToReason(guardResult),
          );
          if (!request.isNotification) {
            responses.add((index: index, response: errorResponse));
          }
          continue;
        }

        if (request.method == 'rpc.discover') {
          if (!_featureFlags.enableSocketNotificationsContract || !request.isNotification) {
            final doc = await _openRpcDocumentLoader.getDocument();
            responses.add((
              index: index,
              response: _responsePreparer.attachRequestTrace(
                request,
                RpcResponse.success(id: request.id, result: doc),
              ),
            ));
          }
          continue;
        }

        final clientToken = _extractClientTokenFromRpcParams(request.params);
        final response = await _dispatcher.dispatch(
          request,
          _agentIdProvider(),
          clientToken: clientToken,
          limits: _protocolProvider().effectiveLimits,
          negotiatedExtensions: _protocolProvider().negotiatedExtensions,
        );
        final tracedResponse = _responsePreparer.attachRequestTrace(request, response);
        _authorizationDecisionLogger.log(
          request: request,
          response: tracedResponse,
          clientToken: clientToken,
        );
        if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
          continue;
        }
        responses.add((index: index, response: tracedResponse));
      }

      if (responses.isEmpty) {
        return;
      }

      final orderedResponses = _supportsOrderedBatchResponses()
          ? (responses.toList()..sort((left, right) => left.index.compareTo(right.index)))
                .map((entry) => entry.response)
                .toList()
          : responses.map((entry) => entry.response).toList();
      await _emitRpcResponse(orderedResponses);
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC batch request',
        error,
        stackTrace,
      );
      // Always answer the hub even on unhandled errors so the request slot is
      // released. Without this the hub would hang on the batch indefinitely.
      final errorResponse = RpcResponse.error(
        id: null,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.internalError,
            technicalMessage: 'Unhandled exception in batch processing',
            extra: {'failure_code': 'unhandled_batch_exception'},
          ),
        ),
      );
      try {
        await _emitRpcResponse(errorResponse);
      } on Object catch (emitError, emitStack) {
        AppLogger.error(
          'Failed to emit batch error response',
          emitError,
          emitStack,
        );
      }
    }
  }

  Future<void> _emitRequestAck(dynamic requestId) async {
    if (requestId == null) return;
    final ackPayload = {
      'request_id': requestId.toString(),
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEvent('rpc:request_ack', ackPayload);
  }

  Future<void> _emitBatchRequestAck(List<RpcRequest> requests) async {
    if (requests.isEmpty) return;
    final ids = requests.where((r) => r.id != null).map((r) => r.id.toString()).toList();
    if (ids.isEmpty) return;
    final ackPayload = {
      'request_ids': ids,
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEvent('rpc:batch_ack', ackPayload);
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
    await _emitRpcResponse(errorResponse);
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

  bool _supportsOrderedBatchResponses() {
    final extensionValue = _protocolProvider().negotiatedExtensions['orderedBatchResponses'];
    if (extensionValue is bool) return extensionValue;
    return true;
  }

  int _validationFailureCode(domain.Failure failure) {
    final code = failure.context['rpc_error_code'];
    return code is int ? code : RpcErrorCode.invalidRequest;
  }

  ({int code, String? reason}) _mapInboundTransportDecodeFailure(domain.Failure failure) {
    if (failure is domain.ValidationFailure && failure.context['transport_signature_invalid'] == true) {
      return (
        code: RpcErrorCode.authenticationFailed,
        reason: RpcErrorCode.reasonInvalidSignature,
      );
    }
    return (code: RpcErrorCode.invalidPayload, reason: null);
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

  int _guardResultToCode(RpcRequestGuardResult result) {
    switch (result) {
      case RpcRequestGuardResult.allow:
        // Invariant: callers must short-circuit when guard returns `allow`,
        // so this arm should be unreachable. The internalError fallback only
        // exists to satisfy the exhaustiveness check; the assert documents
        // the invariant in dev/test builds.
        assert(false, 'guard.allow should not reach error mapping path');
        return RpcErrorCode.internalError;
      case RpcRequestGuardResult.rateLimited:
        return RpcErrorCode.rateLimited;
      case RpcRequestGuardResult.replayDetected:
        return RpcErrorCode.replayDetected;
    }
  }

  /// Distinct reasons for the same RPC code (`-32013 rate_limited`) so the
  /// hub can choose the right back-off strategy:
  /// - `rate_window_exceeded`: too many requests per time window.
  /// - `concurrent_handlers_exceeded`: too many in-flight RPC handlers.
  /// - `replay_detected`: duplicate request id within the replay window.
  String? _guardResultToReason(RpcRequestGuardResult result) {
    switch (result) {
      case RpcRequestGuardResult.allow:
        return null;
      case RpcRequestGuardResult.rateLimited:
        return 'rate_window_exceeded';
      case RpcRequestGuardResult.replayDetected:
        return 'replay_detected';
    }
  }

  String _guardResultToTechnicalMessage(RpcRequestGuardResult result) {
    switch (result) {
      case RpcRequestGuardResult.allow:
        return 'Unexpected guard result';
      case RpcRequestGuardResult.rateLimited:
        return 'Rate limit exceeded for rpc:request';
      case RpcRequestGuardResult.replayDetected:
        return 'Duplicate request id within replay window';
    }
  }
}
