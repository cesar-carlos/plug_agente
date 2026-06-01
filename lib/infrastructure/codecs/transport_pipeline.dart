import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

const int defaultTransportCompressionThresholdBytes = 4096;
const double defaultTransportMaxInflationRatio = 10;

int _jsonEncodeIsolateThresholdBytes(String? metricEventName) {
  if (metricEventName == 'rpc:chunk' || metricEventName == 'rpc:complete') {
    return ConnectionConstants.streamingChunkJsonIsolateThresholdBytes;
  }
  return jsonPayloadIsolateEncodeThresholdBytes;
}

int _outboundRpcChunkRowCount(dynamic data) {
  if (data is! Map) {
    return 0;
  }
  final rows = data['rows'];
  if (rows is List) {
    return rows.length;
  }
  return 0;
}

bool _shouldEncodeJsonInIsolate(
  dynamic data,
  String? metricEventName,
  int budgetBytes,
) {
  if (metricEventName == 'rpc:chunk' &&
      _outboundRpcChunkRowCount(data) >= ConnectionConstants.streamingChunkRowIsolateThreshold) {
    return true;
  }
  return jsonTreeLikelyExceedsByteBudget(data, budgetBytes);
}

Map<String, dynamic> _transportContext(
  int rpcErrorCode,
  Map<String, dynamic> context,
) {
  return <String, dynamic>{
    ...context,
    'rpc_error_code': rpcErrorCode,
  };
}

domain.Failure _withTransportRpcErrorCode(
  domain.Failure failure,
  int rpcErrorCode,
) {
  if (failure.context['rpc_error_code'] is int) {
    return failure;
  }
  final context = _transportContext(rpcErrorCode, failure.context);
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

Object _jsonDecodeUtf8PayloadInIsolate(Uint8List bytes) {
  final jsonString = utf8.decode(bytes);
  final decoded = jsonDecode(jsonString);
  if (decoded == null) {
    throw const FormatException('Top-level JSON payload must not be null');
  }
  return decoded as Object;
}

/// Top-level for [compute]: JSON-serializable values only.
Uint8List jsonUtf8EncodePayloadInIsolate(Object? data) {
  final raw = JsonUtf8Encoder().convert(data);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}

Uint8List _compressGzipInIsolate(Uint8List data) {
  final compressedBytes = GZipEncoder().encode(data);
  if (compressedBytes == null) {
    throw StateError('GZipEncoder returned null');
  }
  return Uint8List.fromList(compressedBytes);
}

Uint8List _decompressGzipInIsolate(Uint8List compressed) {
  final decompressedBytes = GZipDecoder().decodeBytes(compressed);
  return Uint8List.fromList(decompressedBytes);
}

bool _shouldRunGzipCompression(
  String compressionMode,
  int originalSize,
  int compressionThreshold,
) {
  if (compressionMode == 'none' || originalSize < compressionThreshold) {
    return false;
  }
  return compressionMode == 'gzip' || compressionMode == 'auto';
}

bool _exceedsInflationRatio(
  int originalSize,
  int compressedSize,
  double maxInflationRatio,
) {
  return compressedSize > 0 && originalSize / compressedSize > maxInflationRatio;
}

Uint8List? _payloadBytesFromFramePayload(dynamic payload) {
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

/// Transport pipeline for encoding/compressing and decoding/decompressing payloads.
///
/// Handles the complete bidirectional flow:
/// Send: data -> encode -> compress -> frame
/// Receive: frame -> decompress -> decode -> data
class TransportPipeline {
  TransportPipeline({
    required this.encoding,
    required this.compression,
    this.compressionThreshold = defaultTransportCompressionThresholdBytes,
    this.maxInflationRatio = defaultTransportMaxInflationRatio,
    this.gzipIsolateThresholdBytes = ConnectionConstants.defaultGzipIsolateThresholdBytes,
    this.schemaVersion = '1.0',
    this.protocol = 'jsonrpc-v2',
    this.metricsCollector,
  });

  /// Selected encoding format.
  final String encoding;

  /// Send-path compression: `none`, `gzip`, or `auto` (try GZIP; use wire `gzip`
  /// only if smaller than raw UTF-8). Received frames only use `none`/`gzip`.
  final String compression;

  /// Minimum payload size (bytes) to trigger compression.
  final int compressionThreshold;

  /// Maximum decoded/compressed ratio accepted by peers for gzip frames.
  final double maxInflationRatio;

  /// Minimum payload size (bytes) to run GZIP compress/decompress in a background isolate.
  final int gzipIsolateThresholdBytes;

  /// Schema version for the payload frame.
  final String schemaVersion;

  /// Logical transport protocol associated with the current pipeline instance.
  final String protocol;

  /// Optional collector for transport telemetry.
  final ProtocolMetricsCollector? metricsCollector;

  final _uuid = const Uuid();

  void _recordMetric({
    required String direction,
    required String effectiveCompression,
    required int originalSize,
    required int compressedSize,
    required int totalDurationUs,
    String? eventName,
    int? encodeDurationUs,
    int? compressDurationUs,
    int? decodeDurationUs,
    int? decompressDurationUs,
    bool usedJsonEncodeIsolate = false,
    bool usedGzipCompressIsolate = false,
    bool usedJsonDecodeIsolate = false,
    bool usedGzipDecompressIsolate = false,
  }) {
    metricsCollector?.record(
      ProtocolMetrics(
        timestamp: DateTime.now().toUtc(),
        protocol: protocol,
        encoding: encoding,
        compression: effectiveCompression,
        requestedCompression: compression,
        originalSize: originalSize,
        compressedSize: compressedSize,
        direction: direction,
        eventName: eventName,
        totalDurationUs: totalDurationUs,
        encodeDurationUs: encodeDurationUs,
        compressDurationUs: compressDurationUs,
        decodeDurationUs: decodeDurationUs,
        decompressDurationUs: decompressDurationUs,
        usedIsolate:
            usedJsonEncodeIsolate || usedGzipCompressIsolate || usedJsonDecodeIsolate || usedGzipDecompressIsolate,
        usedJsonEncodeIsolate: usedJsonEncodeIsolate,
        usedGzipCompressIsolate: usedGzipCompressIsolate,
        usedJsonDecodeIsolate: usedJsonDecodeIsolate,
        usedGzipDecompressIsolate: usedGzipDecompressIsolate,
      ),
    );
  }

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

      // 1. Encode
      final codec = PayloadCodecFactory.getCodec(encoding);
      final encodeResult = codec.encode(data);

      if (encodeResult.isError()) {
        return Failure(encodeResult.exceptionOrNull()!);
      }

      final encodedBytes = encodeResult.getOrThrow();
      encodeStopwatch.stop();
      final originalSize = encodedBytes.length;

      // 2. Compress (if threshold met and mode requests gzip or auto)
      final shouldCompress = _shouldRunGzipCompression(
        compression,
        originalSize,
        compressionThreshold,
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
        final exceedsInflationRatio = _exceedsInflationRatio(
          originalSize,
          compressedBytes.length,
          maxInflationRatio,
        );
        if ((compression == 'auto' && compressedBytes.length >= originalSize) || exceedsInflationRatio) {
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

      // 3. Create frame
      final frame = PayloadFrame(
        schemaVersion: schemaVersion,
        enc: encoding,
        cmp: finalCompression,
        contentType: codec.contentType,
        originalSize: originalSize,
        compressedSize: compressedSize,
        payload: finalBytes,
        traceId: traceId ?? _uuid.v4(),
        requestId: requestId,
      );

      totalStopwatch.stop();
      _recordMetric(
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
      final jsonEncodeThreshold = _jsonEncodeIsolateThresholdBytes(metricEventName);
      if (encoding == 'json' &&
          _shouldEncodeJsonInIsolate(
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
      final shouldCompress = _shouldRunGzipCompression(
        compression,
        originalSize,
        compressionThreshold,
      );

      Uint8List finalBytes;
      String finalCompression;
      int compressedSize;
      int? compressDurationUs;
      var usedGzipCompressIsolate = false;

      if (shouldCompress) {
        final useIsolate = originalSize >= gzipIsolateThresholdBytes;
        final Uint8List compressedBytes;
        final compressStopwatch = Stopwatch()..start();
        if (useIsolate) {
          usedGzipCompressIsolate = true;
          compressedBytes = await compute(_compressGzipInIsolate, encodedBytes);
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
        final exceedsInflationRatio = _exceedsInflationRatio(
          originalSize,
          compressedBytes.length,
          maxInflationRatio,
        );
        if ((compression == 'auto' && compressedBytes.length >= originalSize) || exceedsInflationRatio) {
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
        traceId: traceId ?? _uuid.v4(),
        requestId: requestId,
      );

      totalStopwatch.stop();
      _recordMetric(
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
      // Validate frame encoding matches pipeline configuration
      if (frame.enc != encoding) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: _transportContext(
              RpcErrorCode.invalidPayload,
              {'expected': encoding, 'actual': frame.enc},
            ),
          ),
        );
      }

      final bytes = _payloadBytesFromFramePayload(frame.payload);
      if (bytes == null) {
        final payloadType = frame.payload.runtimeType.toString();
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame payload is not binary data',
            context: _transportContext(
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

      // 1. Decompress (if needed)
      Uint8List decodableBytes;
      int? decompressDurationUs;

      if (frame.cmp != 'none') {
        final decompressStopwatch = Stopwatch()..start();
        final compressionCodec = CompressionCodecFactory.getCodec(frame.cmp);
        final decompressResult = compressionCodec.decompress(bytes);

        if (decompressResult.isError()) {
          return Failure(
            _withTransportRpcErrorCode(
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

      // 2. Decode
      final decodeStopwatch = Stopwatch()..start();
      final codec = PayloadCodecFactory.getCodec(frame.enc);
      final decodeResult = codec.decode(decodableBytes);

      if (decodeResult.isError()) {
        return Failure(
          _withTransportRpcErrorCode(
            decodeResult.exceptionOrNull()! as domain.Failure,
            RpcErrorCode.decodingFailed,
          ),
        );
      }

      final decoded = decodeResult.getOrThrow() as Object;
      decodeStopwatch.stop();
      totalStopwatch.stop();
      _recordMetric(
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
            context: _transportContext(
              RpcErrorCode.invalidPayload,
              {'expected': encoding, 'actual': frame.enc},
            ),
          ),
        );
      }

      final bytes = _payloadBytesFromFramePayload(frame.payload);
      if (bytes == null) {
        final payloadType = frame.payload.runtimeType.toString();
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame payload is not binary data',
            context: _transportContext(
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
            decodableBytes = await compute(_decompressGzipInIsolate, bytes);
          } on Object catch (error) {
            return Failure(
              domain.CompressionFailure.withContext(
                message: 'Failed to decompress with GZIP',
                cause: error,
                context: _transportContext(
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
              _withTransportRpcErrorCode(
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
            _jsonDecodeUtf8PayloadInIsolate,
            decodableBytes,
          );
        } on Object catch (error) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to decode JSON payload',
              cause: error,
              context: _transportContext(
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
            _withTransportRpcErrorCode(
              decodeResult.exceptionOrNull()! as domain.Failure,
              RpcErrorCode.decodingFailed,
            ),
          );
        }

        decoded = decodeResult.getOrThrow() as Object;
      }

      decodeStopwatch.stop();
      totalStopwatch.stop();
      _recordMetric(
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

  /// Creates a frame from raw bytes (for legacy compatibility).
  PayloadFrame frameFromBytes(Uint8List bytes, {String? requestId}) {
    return PayloadFrame(
      schemaVersion: schemaVersion,
      enc: encoding,
      cmp: 'none',
      contentType: PayloadCodecFactory.getCodec(encoding).contentType,
      originalSize: bytes.length,
      compressedSize: bytes.length,
      payload: bytes,
      traceId: _uuid.v4(),
      requestId: requestId,
    );
  }
}
