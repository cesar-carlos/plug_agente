import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_chunk_transport_policy.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_helpers.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_isolate.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Send-path encode/compress/frame operations for the transport pipeline.
mixin TransportPipelineSend {
  String get encoding;
  String get compression;
  int get compressionThreshold;
  double get maxInflationRatio;
  int get gzipIsolateThresholdBytes;
  String get schemaVersion;
  String get protocol;
  ProtocolMetricsCollector? get metricsCollector;
  Uuid get pipelineUuid;

  /// Prepares a payload for sending.
  ///
  /// Flow: data -> encode -> compress (if needed) -> frame
  Result<PayloadFrame> prepareSend(
    dynamic data, {
    String? traceId,
    String? requestId,
    String? metricEventName,
  }) {
    try {
      final totalStopwatch = Stopwatch()..start();
      final encodeStopwatch = Stopwatch()..start();

      final codec = PayloadCodecFactory.getCodec(encoding);
      final encodeResult = codec.encode(data);

      if (encodeResult.isError()) {
        return Failure(encodeResult.exceptionOrNull()!);
      }

      final encodedBytes = encodeResult.getOrThrow();
      encodeStopwatch.stop();
      final originalSize = encodedBytes.length;

      final shouldCompress = RpcChunkTransportPolicy.shouldCompressPayload(
        compressionMode: compression,
        originalSize: originalSize,
        compressionThreshold: RpcChunkTransportPolicy.compressionThresholdBytes(
          metricEventName,
          defaultThreshold: compressionThreshold,
        ),
        metricEventName: metricEventName,
        payload: data,
      );

      Uint8List finalBytes;
      String finalCompression;
      int compressedSize;
      int? compressDurationUs;

      if (shouldCompress) {
        final compressStopwatch = Stopwatch()..start();
        final gzipCodec = CompressionCodecFactory.getCodec('gzip');
        final compressResult = gzipCodec.compress(encodedBytes);

        if (compressResult.isError()) {
          return Failure(compressResult.exceptionOrNull()!);
        }

        final compressedBytes = compressResult.getOrThrow();
        compressStopwatch.stop();
        compressDurationUs = compressStopwatch.elapsedMicroseconds;
        final inflationExceeded = exceedsInflationRatio(
          originalSize,
          compressedBytes.length,
          maxInflationRatio,
        );
        if ((compression == 'auto' && compressedBytes.length >= originalSize) || inflationExceeded) {
          finalBytes = encodedBytes;
          finalCompression = 'none';
          compressedSize = originalSize;
        } else {
          finalBytes = compressedBytes;
          finalCompression = 'gzip';
          compressedSize = compressedBytes.length;
        }
      } else {
        finalBytes = encodedBytes;
        finalCompression = 'none';
        compressedSize = originalSize;
      }

      final frame = PayloadFrame(
        schemaVersion: schemaVersion,
        enc: encoding,
        cmp: finalCompression,
        contentType: codec.contentType,
        originalSize: originalSize,
        compressedSize: compressedSize,
        payload: finalBytes,
        traceId: traceId ?? pipelineUuid.v4(),
        requestId: requestId,
      );

      totalStopwatch.stop();
      recordTransportPipelineMetric(
        metricsCollector: metricsCollector,
        protocol: protocol,
        encoding: encoding,
        compression: compression,
        direction: 'send',
        eventName: metricEventName,
        effectiveCompression: finalCompression,
        originalSize: originalSize,
        compressedSize: compressedSize,
        totalDurationUs: totalStopwatch.elapsedMicroseconds,
        encodeDurationUs: encodeStopwatch.elapsedMicroseconds,
        compressDurationUs: compressDurationUs,
      );
      return Success(frame);
    } on Object catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to prepare payload for sending',
          cause: error,
          context: {
            'operation': 'prepareSend',
            'encoding': encoding,
            'compression': compression,
          },
        ),
      );
    }
  }

  /// Async variant: uses [compute] for gzip when payload exceeds
  /// [gzipIsolateThresholdBytes] to avoid jank on the main isolate.
  Future<Result<PayloadFrame>> prepareSendAsync(
    dynamic data, {
    String? traceId,
    String? requestId,
    String? metricEventName,
  }) async {
    try {
      final totalStopwatch = Stopwatch()..start();
      final codec = PayloadCodecFactory.getCodec(encoding);
      final encodeStopwatch = Stopwatch()..start();
      late final Uint8List encodedBytes;
      var usedJsonEncodeIsolate = false;
      final jsonEncodeThreshold = jsonEncodeIsolateThresholdBytes(metricEventName);
      if (encoding == 'json' &&
          shouldEncodeJsonInIsolate(
            data,
            metricEventName,
            jsonEncodeThreshold,
          )) {
        usedJsonEncodeIsolate = true;
        try {
          encodedBytes = await compute(jsonUtf8EncodePayloadInIsolate, data);
        } on Object catch (error) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to encode JSON in isolate',
              cause: error,
              context: {'operation': 'jsonEncode', 'encoding': 'json'},
            ),
          );
        }
      } else {
        final encodeResult = codec.encode(data);
        if (encodeResult.isError()) {
          return Failure(encodeResult.exceptionOrNull()!);
        }
        encodedBytes = encodeResult.getOrThrow();
      }
      encodeStopwatch.stop();
      final originalSize = encodedBytes.length;
      final shouldCompress = RpcChunkTransportPolicy.shouldCompressPayload(
        compressionMode: compression,
        originalSize: originalSize,
        compressionThreshold: RpcChunkTransportPolicy.compressionThresholdBytes(
          metricEventName,
          defaultThreshold: compressionThreshold,
        ),
        metricEventName: metricEventName,
        payload: data,
      );

      Uint8List finalBytes;
      String finalCompression;
      int compressedSize;
      int? compressDurationUs;
      var usedGzipCompressIsolate = false;

      if (shouldCompress) {
        final useIsolate =
            originalSize >=
            RpcChunkTransportPolicy.gzipIsolateThresholdBytes(
              metricEventName,
              defaultThreshold: gzipIsolateThresholdBytes,
            );
        final Uint8List compressedBytes;
        final compressStopwatch = Stopwatch()..start();
        if (useIsolate) {
          usedGzipCompressIsolate = true;
          compressedBytes = await compute(compressGzipInIsolate, encodedBytes);
        } else {
          final gzipCodec = CompressionCodecFactory.getCodec('gzip');
          final compressResult = gzipCodec.compress(encodedBytes);
          if (compressResult.isError()) {
            return Failure(compressResult.exceptionOrNull()!);
          }
          compressedBytes = compressResult.getOrThrow();
        }
        compressStopwatch.stop();
        compressDurationUs = compressStopwatch.elapsedMicroseconds;
        final inflationExceeded = exceedsInflationRatio(
          originalSize,
          compressedBytes.length,
          maxInflationRatio,
        );
        if ((compression == 'auto' && compressedBytes.length >= originalSize) || inflationExceeded) {
          finalBytes = encodedBytes;
          finalCompression = 'none';
          compressedSize = originalSize;
        } else {
          finalBytes = compressedBytes;
          finalCompression = 'gzip';
          compressedSize = compressedBytes.length;
        }
      } else {
        finalBytes = encodedBytes;
        finalCompression = 'none';
        compressedSize = originalSize;
      }

      final frame = PayloadFrame(
        schemaVersion: schemaVersion,
        enc: encoding,
        cmp: finalCompression,
        contentType: codec.contentType,
        originalSize: originalSize,
        compressedSize: compressedSize,
        payload: finalBytes,
        traceId: traceId ?? pipelineUuid.v4(),
        requestId: requestId,
      );

      totalStopwatch.stop();
      recordTransportPipelineMetric(
        metricsCollector: metricsCollector,
        protocol: protocol,
        encoding: encoding,
        compression: compression,
        direction: 'send',
        eventName: metricEventName,
        effectiveCompression: finalCompression,
        originalSize: originalSize,
        compressedSize: compressedSize,
        totalDurationUs: totalStopwatch.elapsedMicroseconds,
        encodeDurationUs: encodeStopwatch.elapsedMicroseconds,
        compressDurationUs: compressDurationUs,
        usedJsonEncodeIsolate: usedJsonEncodeIsolate,
        usedGzipCompressIsolate: usedGzipCompressIsolate,
      );
      return Success(frame);
    } on Object catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to prepare payload for sending',
          cause: error,
          context: {
            'operation': 'prepareSendAsync',
            'encoding': encoding,
            'compression': compression,
          },
        ),
      );
    }
  }
}
