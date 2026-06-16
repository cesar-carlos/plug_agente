import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_helpers.dart';

/// Transport tuning dedicated to `rpc:chunk` / `rpc:complete` hot paths.
///
/// Streaming chunks are smaller and more frequent than bulk `rpc:response`
/// payloads; isolate and gzip thresholds are tuned separately so columnar wire
/// chunks do not inherit row-map heuristics meant for large responses.
final class RpcChunkTransportPolicy {
  RpcChunkTransportPolicy._();

  static bool isRpcChunkEvent(String? metricEventName) =>
      metricEventName == 'rpc:chunk' || metricEventName == 'rpc:complete';

  static bool outboundRpcChunkHasColumnar(dynamic data) {
    if (data is! Map) {
      return false;
    }
    final columnar = data['columnar'];
    return columnar is Map && columnar.isNotEmpty;
  }

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

  /// Columnar `rpc:chunk` payloads are typically low compressibility; gzip is
  /// skipped unless [ConnectionConstants.rpcChunkColumnarGzipEnabled] is true.
  static bool shouldCompressPayload({
    required String compressionMode,
    required int originalSize,
    required int compressionThreshold,
    String? metricEventName,
    dynamic payload,
  }) {
    if (!shouldRunGzipCompression(compressionMode, originalSize, compressionThreshold)) {
      return false;
    }
    if (isRpcChunkEvent(metricEventName) &&
        outboundRpcChunkHasColumnar(payload) &&
        !ConnectionConstants.rpcChunkColumnarGzipEnabled) {
      return false;
    }
    return true;
  }
}
