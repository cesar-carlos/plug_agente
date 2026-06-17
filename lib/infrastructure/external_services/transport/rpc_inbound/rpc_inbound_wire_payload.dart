import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';

/// Socket.IO wire shape for inbound `rpc:request`: payload plus optional ack callback.
class RpcInboundWirePayload {
  const RpcInboundWirePayload({
    required this.payload,
    this.socketAck,
  });

  final dynamic payload;
  final void Function()? socketAck;
}

RpcInboundWirePayload unwrapRpcInboundWirePayload(dynamic data) {
  if (data is List && data.length == 2 && data[1] is Function) {
    return RpcInboundWirePayload(
      payload: data[0],
      socketAck: data[1] as void Function(),
    );
  }
  return RpcInboundWirePayload(payload: data);
}

class RpcInboundBestEffortRequestIdentity {
  const RpcInboundBestEffortRequestIdentity({
    this.id,
    this.method,
  });

  final dynamic id;
  final Object? method;
}

RpcInboundBestEffortRequestIdentity extractBestEffortRequestIdentityForRateLimit(
  dynamic payload, {
  required PayloadFrameCodec frameCodec,
}) {
  try {
    if (payload is Map<String, dynamic> && frameCodec.looksLikePayloadFrame(payload)) {
      final decodeResult = frameCodec.decodeIncoming(payload, sourceEvent: 'rpc:request');
      if (decodeResult.isSuccess()) {
        final decodedPayload = decodeResult.getOrThrow();
        if (decodedPayload is Map<String, dynamic>) {
          return RpcInboundBestEffortRequestIdentity(
            id: decodedPayload['id'],
            method: decodedPayload['method'],
          );
        }
      }
      return const RpcInboundBestEffortRequestIdentity();
    }
    if (payload is Map<String, dynamic>) {
      return RpcInboundBestEffortRequestIdentity(
        id: payload['id'],
        method: payload['method'],
      );
    }
    return const RpcInboundBestEffortRequestIdentity();
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'Failed to extract request identity while building rate-limited response',
      error,
      stackTrace,
    );
    return const RpcInboundBestEffortRequestIdentity();
  }
}

dynamic extractRequestIdFromRpcWirePayload(
  dynamic payload, {
  required PayloadFrameCodec frameCodec,
}) {
  if (frameCodec.looksLikePayloadFrame(payload)) {
    return (payload as Map<String, dynamic>)['requestId'];
  }
  if (payload is Map<String, dynamic>) {
    return payload['id'] ?? payload['request_id'];
  }
  return null;
}
