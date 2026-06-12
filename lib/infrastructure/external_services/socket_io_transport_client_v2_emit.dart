part of 'socket_io_transport_client_v2.dart';

abstract base class _SocketIoTransportHost {
  FeatureFlags get featureFlags;
  PayloadLogSummarizer get logSummarizer;
  void Function(String direction, String event, dynamic data)? get onMessage;
  TransportRpcPipelineBundle get pipeline;
  TransportConnectionLifecycle get lifecycle;
  bool get usesBinaryTransport;
  LogRateLimiter get diagnosticLogLimiter;
}

base mixin _SocketIoTransportEmit on _SocketIoTransportHost {
  void _logMessage(String direction, String event, dynamic data) {
    final messageCallback = onMessage;
    if (messageCallback == null) {
      return;
    }
    final compacted = SqlRpcLogPayloadCompactor.compactSocketLogPayload(event, data);
    final traced = featureFlags.enableSocketSummarizeLargePayloadLogs && compacted != null
        ? logSummarizer.summarize(direction, event, compacted)
        : compacted;
    scheduleMicrotask(() => messageCallback(direction, event, traced));
  }

  Future<void> _emitRpcResponse(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) {
    return pipeline.rpcResponseDeliveryCoordinator.emit(
      responseData,
      methodsById: methodsById,
    );
  }

  void _emitEvent(String event, dynamic logicalPayload) {
    unawaited(
      _emitEventAsync(event, logicalPayload).catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Unhandled socket emit failure for $event',
          error,
          stackTrace,
        );
        return false;
      }),
    );
  }

  Future<bool> _emitEventAsync(String event, dynamic logicalPayload) async {
    final socket = lifecycle.socket;
    if (socket == null) {
      return false;
    }
    final outgoingResult = await _prepareOutgoingPayloadAsync(
      event,
      logicalPayload,
    );
    if (outgoingResult.isError()) {
      AppLogger.warning(
        '_emitEventAsync: failed to encode $event — frame dropped',
        outgoingResult.exceptionOrNull(),
      );
      return false;
    }
    final outgoingPayload = outgoingResult.getOrThrow();
    try {
      socket.emit(event, outgoingPayload);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Socket emit failed for $event',
        error,
        stackTrace,
      );
      return false;
    }
    _logMessage('SENT', event, logicalPayload);
    return true;
  }

  Future<void> _emitEventVoid(String event, dynamic logicalPayload) async {
    await _emitEventAsync(event, logicalPayload);
  }

  Future<Result<Map<String, dynamic>>> _prepareOutgoingPayloadAsync(
    String event,
    dynamic logicalPayload,
  ) async {
    if (!usesBinaryTransport) {
      AppLogger.error(
        'Attempted to emit $event without negotiated binary PayloadFrame transport',
      );
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Binary PayloadFrame transport is not negotiated',
          context: {
            'event': event,
            'rpc_error_code': RpcErrorCode.internalError,
          },
        ),
      );
    }
    return pipeline.frameCodec.prepareOutgoing(
      event: event,
      logicalPayload: logicalPayload,
    );
  }

  void _publishLargeResponseAdvice({
    required String event,
    required dynamic logicalPayload,
  }) {
    if (event != 'rpc:response') {
      return;
    }
    final streamingChunks = featureFlags.enableSocketStreamingChunks;
    final streamingFromDb = featureFlags.enableSocketStreamingFromDb;
    final backpressure = featureFlags.enableSocketBackpressure;
    if (streamingChunks && streamingFromDb && backpressure) {
      return;
    }
    const category = 'large_rpc_response_without_full_streaming';
    if (!diagnosticLogLimiter.shouldLog(category)) {
      return;
    }
    if (!jsonTreeLikelyExceedsByteBudget(
      logicalPayload,
      ConnectionConstants.socketOutgoingContractValidationMaxBytes,
    )) {
      return;
    }
    final diagnostic = <String, dynamic>{
      'event': event,
      'threshold_bytes': ConnectionConstants.socketOutgoingContractValidationMaxBytes,
      'streaming_chunks_enabled': streamingChunks,
      'streaming_from_db_enabled': streamingFromDb,
      'backpressure_enabled': backpressure,
      'recommendation': 'Enable DB streaming, rpc:chunk, and rpc:stream.pull backpressure for large result sets.',
      'count': diagnosticLogLimiter.countFor(category),
    };
    _logMessage('PERFORMANCE', 'rpc:response:large_payload_advice', diagnostic);
    AppLogger.warning(
      'Large rpc:response is being materialized without the full streaming/backpressure path '
      '(count=${diagnosticLogLimiter.countFor(category)}, '
      'streaming_chunks=$streamingChunks, streaming_from_db=$streamingFromDb, backpressure=$backpressure)',
    );
  }

  dynamic _decodeIncomingPayloadOrThrow(
    dynamic payload, {
    String? sourceEvent,
  }) {
    return pipeline.frameCodec.decodeIncoming(payload, sourceEvent: sourceEvent).getOrThrow();
  }

  Future<Result<void>> _sendRpcResponse(QueryResponse response) async {
    try {
      final rpcResponse = QueryResponseRpcMapper.toRpcResponse(response);
      await _emitRpcResponse(rpcResponse);

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to send RPC response',
          cause: e,
          context: {'operation': 'sendRpcResponse'},
        ),
      );
    }
  }

  Future<void> _emitInternalErrorResponse(dynamic requestId) async {
    final socket = lifecycle.socket;
    if (socket == null) return;
    try {
      final errorResponse = RpcResponse.error(
        id: requestId,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
        ),
      );
      final prepared = pipeline.responsePreparer.prepareForSend(errorResponse);
      final validatedResult = pipeline.responsePreparer.validateOutgoing(prepared);
      if (validatedResult.isError()) {
        AppLogger.warning(
          'Fallback rpc:response failed contract validation',
          validatedResult.exceptionOrNull(),
        );
        return;
      }
      final outgoingResult = await _prepareOutgoingPayloadAsync(
        'rpc:response',
        validatedResult.getOrThrow(),
      );
      if (outgoingResult.isError()) {
        AppLogger.warning(
          'Fallback rpc:response could not be framed as PayloadFrame',
          outgoingResult.exceptionOrNull(),
        );
        return;
      }
      final outgoingPayload = outgoingResult.getOrThrow();
      _logMessage('SENT', 'rpc:response', validatedResult.getOrThrow());
      socket.emit('rpc:response', outgoingPayload);
    } on Object catch (e, st) {
      AppLogger.warning('Failed to emit fallback internal error response', e, st);
    }
  }
}
