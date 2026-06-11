import 'dart:typed_data';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

int jsonEncodeIsolateThresholdBytes(String? metricEventName) {
  if (metricEventName == 'rpc:chunk' || metricEventName == 'rpc:complete') {
    return ConnectionConstants.streamingChunkJsonIsolateThresholdBytes;
  }
  return jsonPayloadIsolateEncodeThresholdBytes;
}

int outboundRpcChunkRowCount(dynamic data) {
  if (data is! Map) {
    return 0;
  }
  final rows = data['rows'];
  if (rows is List) {
    return rows.length;
  }
  return 0;
}

bool shouldEncodeJsonInIsolate(
  dynamic data,
  String? metricEventName,
  int budgetBytes,
) {
  if (metricEventName == 'rpc:chunk' &&
      outboundRpcChunkRowCount(data) >= ConnectionConstants.streamingChunkRowIsolateThreshold) {
    return true;
  }
  return jsonTreeLikelyExceedsByteBudget(data, budgetBytes);
}

Map<String, dynamic> transportContext(
  int rpcErrorCode,
  Map<String, dynamic> context,
) {
  return <String, dynamic>{
    ...context,
    'rpc_error_code': rpcErrorCode,
  };
}

domain.Failure withTransportRpcErrorCode(
  domain.Failure failure,
  int rpcErrorCode,
) {
  if (failure.context['rpc_error_code'] is int) {
    return failure;
  }
  final context = transportContext(rpcErrorCode, failure.context);
  return switch (failure) {
    domain.CompressionFailure() => domain.CompressionFailure.withContext(
      message: failure.message,
      cause: failure.cause,
      timestamp: failure.timestamp,
      context: context,
    ),
    domain.ValidationFailure() => domain.ValidationFailure.withContext(
      message: failure.message,
      cause: failure.cause,
      timestamp: failure.timestamp,
      context: context,
    ),
    _ => domain.ValidationFailure.withContext(
      message: failure.message,
      cause: failure.cause,
      timestamp: failure.timestamp,
      context: context,
    ),
  };
}

bool shouldRunGzipCompression(
  String compressionMode,
  int originalSize,
  int compressionThreshold,
) {
  if (compressionMode == 'none' || originalSize < compressionThreshold) {
    return false;
  }
  return compressionMode == 'gzip' || compressionMode == 'auto';
}

bool exceedsInflationRatio(
  int originalSize,
  int compressedSize,
  double maxInflationRatio,
) {
  return compressedSize > 0 && originalSize / compressedSize > maxInflationRatio;
}

Uint8List? payloadBytesFromFramePayload(dynamic payload) {
  return switch (payload) {
    final Uint8List value => value,
    final ByteBuffer value => value.asUint8List(),
    final TypedData value => Uint8List.view(
      value.buffer,
      value.offsetInBytes,
      value.lengthInBytes,
    ),
    final List<int> value => Uint8List.fromList(value),
    _ => null,
  };
}
