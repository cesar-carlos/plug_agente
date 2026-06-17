import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_request_context.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_response_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_wire_payload.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';

/// Builds and emits rate-limited responses for concurrency-cap rejections.
class RpcInboundRateLimitResponder {
  RpcInboundRateLimitResponder({
    required PayloadFrameCodec frameCodec,
    required RpcResponsePreparer responsePreparer,
    required RpcInboundResponseEmitter responseEmitter,
  }) : _frameCodec = frameCodec,
       _responsePreparer = responsePreparer,
       _responseEmitter = responseEmitter;

  final PayloadFrameCodec _frameCodec;
  final RpcResponsePreparer _responsePreparer;
  final RpcInboundResponseEmitter _responseEmitter;

  Future<void> emitConcurrencyLimitedError(dynamic rawData) async {
    final wirePayload = unwrapRpcInboundWirePayload(rawData);
    try {
      final identity = extractBestEffortRequestIdentityForRateLimit(
        wirePayload.payload,
        frameCodec: _frameCodec,
      );
      await _responseEmitter.emit(
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
        methodsById: rpcInboundMethodsByIdForValidationError(
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
}
