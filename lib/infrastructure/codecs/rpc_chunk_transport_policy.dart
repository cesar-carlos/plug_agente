import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';

/// Transport tuning dedicated to `rpc:chunk` / `rpc:complete` hot paths.
///
/// Streaming chunks are smaller and more frequent than bulk `rpc:response`
/// payloads; isolate and gzip thresholds are tuned separately so columnar wire
/// chunks do not inherit row-map heuristics meant for large responses.
final class RpcChunkTransportPolicy {
  RpcChunkTransportPolicy._();

  static bool isRpcChunkEvent(String? metricEventName) =>
      metricEventName == 'rpc:chunk' || metricEventName == 'rpc:complete';

  static int jsonEncodeIsolateThresholdBytes(String? metricEventName) {
    if (!isRpcChunkEvent(metricEventName)) {
      return jsonPayloadIsolateEncodeThresholdBytes;
    }
    return ConnectionConstants.rpcChunkJsonIsolateThresholdBytes;
  }

  static int gzipIsolateThresholdBytes(
    String? metricEventName, {
    required int defaultThreshold,
  }) {
    if (!isRpcChunkEvent(metricEventName)) {
      return defaultThreshold;
    }
    return ConnectionConstants.rpcChunkGzipIsolateThresholdBytes;
  }

  static int compressionThresholdBytes(
    String? metricEventName, {
    required int defaultThreshold,
  }) {
    if (!isRpcChunkEvent(metricEventName)) {
      return defaultThreshold;
    }
    return ConnectionConstants.rpcChunkCompressionThresholdBytes;
  }

  static int rowIsolateThreshold(String? metricEventName) {
    if (!isRpcChunkEvent(metricEventName)) {
      return ConnectionConstants.streamingChunkRowIsolateThreshold;
    }
    return ConnectionConstants.rpcChunkRowIsolateThreshold;
  }
}
