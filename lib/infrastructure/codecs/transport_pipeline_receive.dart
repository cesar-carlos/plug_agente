import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_helpers.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_isolate.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:result_dart/result_dart.dart';

/// Receive-path decompress/decode operations for the transport pipeline.
mixin TransportPipelineReceive {
  String get encoding;
  double get maxInflationRatio;
  int get gzipIsolateThresholdBytes;
  String get protocol;
  String get compression;
  ProtocolMetricsCollector? get metricsCollector;

  /// Receives and processes a payload frame.
  ///
  /// Flow: frame -> decompress (if needed) -> decode -> data
  Result<dynamic> receiveProcess(
    PayloadFrame frame, {
    int? maxCompressedBytes,
    int? maxOriginalBytes,
    double? maxInflationRatio,
    String? metricEventName,
  }) {
    try {
      final totalStopwatch = Stopwatch()..start();
      final inflationRatioLimit = maxInflationRatio ?? this.maxInflationRatio;
      if (frame.enc != encoding) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: transportContext(
              RpcErrorCode.invalidPayload,
              {'expected': encoding, 'actual': frame.enc},
            ),
          ),
        );
      }

      final bytes = payloadBytesFromFramePayload(frame.payload);
      if (bytes == null) {
        final payloadType = frame.payload.runtimeType.toString();
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame payload is not binary data',
            context: transportContext(
              RpcErrorCode.invalidPayload,
              {'payloadType': payloadType},
            ),
          ),
        );
      }

      if (bytes.length != frame.compressedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame compressed size mismatch: expected ${frame.compressedSize}, got ${bytes.length}',
            context: {
              'expectedCompressedSize': frame.compressedSize,
              'actualCompressedSize': bytes.length,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxCompressedBytes != null && frame.compressedSize > maxCompressedBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Compressed payload exceeds negotiated limit',
            context: {
              'compressedSize': frame.compressedSize,
              'limit': maxCompressedBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxOriginalBytes != null && frame.originalSize > maxOriginalBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Original payload exceeds negotiated limit',
            context: {
              'originalSize': frame.originalSize,
              'limit': maxOriginalBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }

      Uint8List decodableBytes;
      int? decompressDurationUs;

      if (frame.cmp != 'none') {
        final decompressStopwatch = Stopwatch()..start();
        final compressionCodec = CompressionCodecFactory.getCodec(frame.cmp);
        final decompressResult = compressionCodec.decompress(bytes);

        if (decompressResult.isError()) {
          return Failure(
            withTransportRpcErrorCode(
              decompressResult.exceptionOrNull()! as domain.Failure,
              RpcErrorCode.compressionFailed,
            ),
          );
        }

        decodableBytes = decompressResult.getOrThrow();
        decompressStopwatch.stop();
        decompressDurationUs = decompressStopwatch.elapsedMicroseconds;
      } else {
        decodableBytes = bytes;
      }

      if (decodableBytes.length != frame.originalSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame original size mismatch: expected ${frame.originalSize}, got ${decodableBytes.length}',
            context: {
              'expectedOriginalSize': frame.originalSize,
              'actualOriginalSize': decodableBytes.length,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxOriginalBytes != null && decodableBytes.length > maxOriginalBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Decoded payload exceeds negotiated limit',
            context: {
              'decodedSize': decodableBytes.length,
              'limit': maxOriginalBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (bytes.isNotEmpty && decodableBytes.length / bytes.length > inflationRatioLimit) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Payload inflation ratio exceeds allowed maximum',
            context: {
              'decodedSize': decodableBytes.length,
              'compressedSize': bytes.length,
              'maxInflationRatio': inflationRatioLimit,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }

      final decodeStopwatch = Stopwatch()..start();
      final codec = PayloadCodecFactory.getCodec(frame.enc);
      final decodeResult = codec.decode(decodableBytes);

      if (decodeResult.isError()) {
        return Failure(
          withTransportRpcErrorCode(
            decodeResult.exceptionOrNull()! as domain.Failure,
            RpcErrorCode.decodingFailed,
          ),
        );
      }

      final decoded = decodeResult.getOrThrow() as Object;
      decodeStopwatch.stop();
      totalStopwatch.stop();
      recordTransportPipelineMetric(
        metricsCollector: metricsCollector,
        protocol: protocol,
        encoding: encoding,
        compression: compression,
        direction: 'receive',
        eventName: metricEventName,
        effectiveCompression: frame.cmp,
        originalSize: frame.originalSize,
        compressedSize: frame.compressedSize,
        totalDurationUs: totalStopwatch.elapsedMicroseconds,
        decodeDurationUs: decodeStopwatch.elapsedMicroseconds,
        decompressDurationUs: decompressDurationUs,
      );
      return Success(decoded);
    } on Object catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to process received payload',
          cause: error,
          context: {
            'operation': 'receiveProcess',
            'frameEncoding': frame.enc,
            'frameCompression': frame.cmp,
            'rpc_error_code': RpcErrorCode.compressionFailed,
          },
        ),
      );
    }
  }

  /// Like [receiveProcess], but runs GZIP decompression in an isolate when
  /// [PayloadFrame.originalSize] is at least [gzipIsolateThresholdBytes].
  Future<Result<dynamic>> receiveProcessAsync(
    PayloadFrame frame, {
    int? maxCompressedBytes,
    int? maxOriginalBytes,
    double? maxInflationRatio,
    String? metricEventName,
  }) async {
    try {
      final totalStopwatch = Stopwatch()..start();
      final inflationRatioLimit = maxInflationRatio ?? this.maxInflationRatio;
      if (frame.enc != encoding) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: transportContext(
              RpcErrorCode.invalidPayload,
              {'expected': encoding, 'actual': frame.enc},
            ),
          ),
        );
      }

      final bytes = payloadBytesFromFramePayload(frame.payload);
      if (bytes == null) {
        final payloadType = frame.payload.runtimeType.toString();
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame payload is not binary data',
            context: transportContext(
              RpcErrorCode.invalidPayload,
              {'payloadType': payloadType},
            ),
          ),
        );
      }

      if (bytes.length != frame.compressedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame compressed size mismatch: expected ${frame.compressedSize}, got ${bytes.length}',
            context: {
              'expectedCompressedSize': frame.compressedSize,
              'actualCompressedSize': bytes.length,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxCompressedBytes != null && frame.compressedSize > maxCompressedBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Compressed payload exceeds negotiated limit',
            context: {
              'compressedSize': frame.compressedSize,
              'limit': maxCompressedBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxOriginalBytes != null && frame.originalSize > maxOriginalBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Original payload exceeds negotiated limit',
            context: {
              'originalSize': frame.originalSize,
              'limit': maxOriginalBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }

      Uint8List decodableBytes;
      int? decompressDurationUs;
      var usedGzipDecompressIsolate = false;

      if (frame.cmp != 'none') {
        final decompressStopwatch = Stopwatch()..start();
        if (frame.cmp == 'gzip' && frame.originalSize >= gzipIsolateThresholdBytes) {
          usedGzipDecompressIsolate = true;
          try {
            decodableBytes = await compute(decompressGzipInIsolate, bytes);
          } on Object catch (error) {
            return Failure(
              domain.CompressionFailure.withContext(
                message: 'Failed to decompress with GZIP',
                cause: error,
                context: transportContext(
                  RpcErrorCode.compressionFailed,
                  {'operation': 'decompress', 'algorithm': 'gzip'},
                ),
              ),
            );
          }
        } else {
          final compressionCodec = CompressionCodecFactory.getCodec(frame.cmp);
          final decompressResult = compressionCodec.decompress(bytes);

          if (decompressResult.isError()) {
            return Failure(
              withTransportRpcErrorCode(
                decompressResult.exceptionOrNull()! as domain.Failure,
                RpcErrorCode.compressionFailed,
              ),
            );
          }

          decodableBytes = decompressResult.getOrThrow();
        }
        decompressStopwatch.stop();
        decompressDurationUs = decompressStopwatch.elapsedMicroseconds;
      } else {
        decodableBytes = bytes;
      }

      if (decodableBytes.length != frame.originalSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame original size mismatch: expected ${frame.originalSize}, got ${decodableBytes.length}',
            context: {
              'expectedOriginalSize': frame.originalSize,
              'actualOriginalSize': decodableBytes.length,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (maxOriginalBytes != null && decodableBytes.length > maxOriginalBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Decoded payload exceeds negotiated limit',
            context: {
              'decodedSize': decodableBytes.length,
              'limit': maxOriginalBytes,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }
      if (bytes.isNotEmpty && decodableBytes.length / bytes.length > inflationRatioLimit) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Payload inflation ratio exceeds allowed maximum',
            context: {
              'decodedSize': decodableBytes.length,
              'compressedSize': bytes.length,
              'maxInflationRatio': inflationRatioLimit,
              'rpc_error_code': RpcErrorCode.invalidPayload,
            },
          ),
        );
      }

      final Object decoded;
      final decodeStopwatch = Stopwatch()..start();
      var usedJsonDecodeIsolate = false;
      if (frame.enc == 'json' && decodableBytes.length >= jsonPayloadIsolateEncodeThresholdBytes) {
        usedJsonDecodeIsolate = true;
        try {
          decoded = await compute(
            jsonDecodeUtf8PayloadInIsolate,
            decodableBytes,
          );
        } on Object catch (error) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to decode JSON payload',
              cause: error,
              context: transportContext(
                RpcErrorCode.decodingFailed,
                {'operation': 'jsonDecode', 'encoding': 'json'},
              ),
            ),
          );
        }
      } else {
        final codec = PayloadCodecFactory.getCodec(frame.enc);
        final decodeResult = codec.decode(decodableBytes);

        if (decodeResult.isError()) {
          return Failure(
            withTransportRpcErrorCode(
              decodeResult.exceptionOrNull()! as domain.Failure,
              RpcErrorCode.decodingFailed,
            ),
          );
        }

        decoded = decodeResult.getOrThrow() as Object;
      }

      decodeStopwatch.stop();
      totalStopwatch.stop();
      recordTransportPipelineMetric(
        metricsCollector: metricsCollector,
        protocol: protocol,
        encoding: encoding,
        compression: compression,
        direction: 'receive',
        eventName: metricEventName,
        effectiveCompression: frame.cmp,
        originalSize: frame.originalSize,
        compressedSize: frame.compressedSize,
        totalDurationUs: totalStopwatch.elapsedMicroseconds,
        decodeDurationUs: decodeStopwatch.elapsedMicroseconds,
        decompressDurationUs: decompressDurationUs,
        usedJsonDecodeIsolate: usedJsonDecodeIsolate,
        usedGzipDecompressIsolate: usedGzipDecompressIsolate,
      );
      return Success(decoded);
    } on Object catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to process received payload',
          cause: error,
          context: {
            'operation': 'receiveProcessAsync',
            'frameEncoding': frame.enc,
            'frameCompression': frame.cmp,
            'rpc_error_code': RpcErrorCode.compressionFailed,
          },
        ),
      );
    }
  }
}
