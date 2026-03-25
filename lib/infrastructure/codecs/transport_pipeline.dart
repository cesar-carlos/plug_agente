import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Bytes above which **inbound** gzip / JSON uses worker isolates (decode path).
const int gzipIsolateDecodeThresholdBytes = 32 * 1024;

/// Extra slack for **outbound** gzip isolate vs decode: avoids flapping when
/// compressed wire size is smaller than UTF-8 JSON size.
const int gzipIsolateEncodeSlackBytes = 4 * 1024;

/// Threshold for outbound gzip [compute] (encode path).
const int gzipIsolateEncodeThresholdBytes = gzipIsolateDecodeThresholdBytes + gzipIsolateEncodeSlackBytes;

/// Kept for benchmarks/tests; same as [gzipIsolateDecodeThresholdBytes].
const int gzipIsolateThresholdBytes = gzipIsolateDecodeThresholdBytes;

/// Whether inbound processing should use [TransportPipeline.receiveProcessAsync]
/// so gzip decompression and/or JSON decode can run off the UI isolate.
bool incomingPayloadFrameNeedsAsyncDecode(PayloadFrame frame) {
  switch (frame.cmp) {
    case 'gzip':
      return frame.compressedSize >= gzipIsolateDecodeThresholdBytes ||
          frame.originalSize >= gzipIsolateDecodeThresholdBytes;
    case 'none':
      return frame.enc == 'json' && frame.originalSize >= jsonPayloadIsolateEncodeThresholdBytes;
    default:
      return true;
  }
}

Object _jsonDecodeUtf8PayloadInIsolate(Uint8List bytes) {
  final dynamic decoded = utf8.decoder.fuse(json.decoder).convert(bytes);
  return decoded as Object;
}

/// Top-level for [compute]: JSON-serializable values only.
Uint8List jsonUtf8EncodePayloadInIsolate(Object? data) {
  final raw = JsonUtf8Encoder().convert(data);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}

Result<Uint8List> _resolveFramePayloadBytes(PayloadFrame frame) {
  final dynamic payload = frame.payload;
  if (payload is Uint8List) {
    return Success(payload);
  }
  if (payload is Uint8ClampedList) {
    return Success(Uint8List.sublistView(payload));
  }
  if (payload is List<int>) {
    return Success(Uint8List.fromList(payload));
  }
  if (payload is String) {
    try {
      final normalized = base64.normalize(payload);
      return Success(Uint8List.fromList(base64Decode(normalized)));
    } on FormatException catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Frame payload is not valid base64 data',
          cause: error,
          context: {'payloadType': payload.runtimeType.toString()},
        ),
      );
    }
  }
  return Failure(
    domain.ValidationFailure.withContext(
      message: 'Frame payload is not binary data',
      context: {'payloadType': payload.runtimeType.toString()},
    ),
  );
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

/// Transport pipeline for encoding/compressing and decoding/decompressing payloads.
///
/// Handles the complete bidirectional flow:
/// Send: data -> encode -> compress -> frame
/// Receive: frame -> decompress -> decode -> data
///
/// This is the **Socket.IO PayloadFrame** path (binary `payload` + `cmp`/`enc`).
/// For SQL result rows wrapped as JSON maps with `compressed_data` (base64), use
/// `lib/infrastructure/compression/gzip_compressor.dart`.
class TransportPipeline {
  TransportPipeline({
    required this.encoding,
    required this.compression,
    this.compressionThreshold = 1024,
    this.schemaVersion = '1.0',
    this.gzipOutboundZlibLevel = gzipTransportZlibLevel,
  });

  /// Selected encoding format.
  final String encoding;

  /// Send-path compression: `none`, `gzip`, or `auto` (try GZIP; use wire `gzip`
  /// only if smaller than raw UTF-8). Received frames only use `none`/`gzip`.
  final String compression;

  /// Minimum payload size (bytes) to trigger compression.
  final int compressionThreshold;

  /// Schema version for the payload frame.
  final String schemaVersion;

  /// Zlib level for outbound PayloadFrame gzip (`1` = fast). From prefs or
  /// [gzipTransportZlibLevel] default when constructed without override.
  final int gzipOutboundZlibLevel;

  final _uuid = const Uuid();

  /// Prepares a payload for sending.
  ///
  /// Prefer [prepareSendAsync] for real Socket.IO emits so large gzip/JSON can
  /// run in a worker isolate. [prepareSend] suits tests and small sync flows.
  ///
  /// Flow: data -> encode -> compress (if needed) -> frame
  Result<PayloadFrame> prepareSend(
    dynamic data, {
    String? traceId,
    String? requestId,
  }) {
    try {
      // 1. Encode
      final codec = PayloadCodecFactory.getCodec(encoding);
      final encodeResult = codec.encode(data);

      if (encodeResult.isError()) {
        return Failure(encodeResult.exceptionOrNull()!);
      }

      final encodedBytes = encodeResult.getOrThrow();
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

      if (shouldCompress) {
        late final Uint8List compressedBytes;
        try {
          compressedBytes = gzipCompressBytesOrThrow(
            encodedBytes,
            compressionLevel: gzipOutboundZlibLevel,
          );
        } on Object catch (error) {
          return Failure(
            domain.CompressionFailure.withContext(
              message: 'Failed to compress with GZIP',
              cause: error,
              context: {'operation': 'compress', 'algorithm': 'gzip'},
            ),
          );
        }
        if (compression == 'auto' && compressedBytes.length >= originalSize) {
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

      return Success(frame);
    } on Exception catch (error) {
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
  /// [gzipIsolateEncodeThresholdBytes] to avoid jank on the main isolate.
  Future<Result<PayloadFrame>> prepareSendAsync(
    dynamic data, {
    String? traceId,
    String? requestId,
  }) async {
    try {
      final codec = PayloadCodecFactory.getCodec(encoding);
      late final Uint8List encodedBytes;
      if (encoding == 'json' &&
          jsonTreeLikelyExceedsByteBudget(
            data,
            jsonPayloadIsolateEncodeThresholdBytes,
          )) {
        try {
          encodedBytes = await compute(jsonUtf8EncodePayloadInIsolate, data);
        } on Object catch (error) {
          return Failure(
            domain.PayloadEncodingFailure.withContext(
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
      final originalSize = encodedBytes.length;
      final shouldCompress = _shouldRunGzipCompression(
        compression,
        originalSize,
        compressionThreshold,
      );

      Uint8List finalBytes;
      String finalCompression;
      int compressedSize;

      if (shouldCompress) {
        final useIsolate = originalSize >= gzipIsolateEncodeThresholdBytes;
        late final Uint8List compressedBytes;
        if (useIsolate) {
          compressedBytes = await compute(
            gzipCompressWithLevelForIsolate,
            (encodedBytes, gzipOutboundZlibLevel),
          );
        } else {
          try {
            compressedBytes = gzipCompressBytesOrThrow(
              encodedBytes,
              compressionLevel: gzipOutboundZlibLevel,
            );
          } on Object catch (error) {
            return Failure(
              domain.CompressionFailure.withContext(
                message: 'Failed to compress with GZIP',
                cause: error,
                context: {'operation': 'compress', 'algorithm': 'gzip'},
              ),
            );
          }
        }
        if (compression == 'auto' && compressedBytes.length >= originalSize) {
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
    double maxInflationRatio = 30,
  }) {
    try {
      // Validate frame encoding matches pipeline configuration
      if (frame.enc != encoding) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: {'expected': encoding, 'actual': frame.enc},
          ),
        );
      }

      final bytesResult = _resolveFramePayloadBytes(frame);
      if (bytesResult.isError()) {
        return Failure(bytesResult.exceptionOrNull()!);
      }
      final bytes = bytesResult.getOrThrow();

      if (bytes.length != frame.compressedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame compressed size mismatch: expected ${frame.compressedSize}, got ${bytes.length}',
            context: {
              'expectedCompressedSize': frame.compressedSize,
              'actualCompressedSize': bytes.length,
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
            },
          ),
        );
      }

      // 1. Decompress (if needed)
      Uint8List decodableBytes;

      if (frame.cmp != 'none') {
        final compressionCodec = CompressionCodecFactory.getCodec(frame.cmp);
        final decompressResult = compressionCodec.decompress(bytes);

        if (decompressResult.isError()) {
          return Failure(decompressResult.exceptionOrNull()!);
        }

        decodableBytes = decompressResult.getOrThrow();
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
            },
          ),
        );
      }
      if (bytes.isNotEmpty && decodableBytes.length / bytes.length > maxInflationRatio) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Payload inflation ratio exceeds allowed maximum',
            context: {
              'decodedSize': decodableBytes.length,
              'compressedSize': bytes.length,
              'maxInflationRatio': maxInflationRatio,
            },
          ),
        );
      }

      // 2. Decode
      final codec = PayloadCodecFactory.getCodec(frame.enc);
      final decodeResult = codec.decode(decodableBytes);

      if (decodeResult.isError()) {
        return Failure(decodeResult.exceptionOrNull()!);
      }

      final decoded = decodeResult.getOrThrow();
      return Success(decoded as Object);
    } on Exception catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to process received payload',
          cause: error,
          context: {
            'operation': 'receiveProcess',
            'frameEncoding': frame.enc,
            'frameCompression': frame.cmp,
          },
        ),
      );
    }
  }

  /// Like [receiveProcess], but runs GZIP decompression in an isolate when the
  /// compressed payload is at least [gzipIsolateDecodeThresholdBytes].
  Future<Result<dynamic>> receiveProcessAsync(
    PayloadFrame frame, {
    int? maxCompressedBytes,
    int? maxOriginalBytes,
    double maxInflationRatio = 30,
  }) async {
    try {
      if (frame.enc != encoding) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: {'expected': encoding, 'actual': frame.enc},
          ),
        );
      }

      final bytesResult = _resolveFramePayloadBytes(frame);
      if (bytesResult.isError()) {
        return Failure(bytesResult.exceptionOrNull()!);
      }
      final bytes = bytesResult.getOrThrow();

      if (bytes.length != frame.compressedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Frame compressed size mismatch: expected ${frame.compressedSize}, got ${bytes.length}',
            context: {
              'expectedCompressedSize': frame.compressedSize,
              'actualCompressedSize': bytes.length,
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
            },
          ),
        );
      }

      Uint8List decodableBytes;

      if (frame.cmp != 'none') {
        final useGzipIsolate =
            frame.cmp == 'gzip' &&
            (bytes.length >= gzipIsolateDecodeThresholdBytes || frame.originalSize >= gzipIsolateDecodeThresholdBytes);
        if (useGzipIsolate) {
          try {
            decodableBytes = await compute(gzipDecompressBytesOrThrow, bytes);
          } on Object catch (error) {
            return Failure(
              domain.CompressionFailure.withContext(
                message: 'Failed to decompress with GZIP',
                cause: error,
                context: {'operation': 'decompress', 'algorithm': 'gzip'},
              ),
            );
          }
        } else {
          final compressionCodec = CompressionCodecFactory.getCodec(frame.cmp);
          final decompressResult = compressionCodec.decompress(bytes);

          if (decompressResult.isError()) {
            return Failure(decompressResult.exceptionOrNull()!);
          }

          decodableBytes = decompressResult.getOrThrow();
        }
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
            },
          ),
        );
      }
      if (bytes.isNotEmpty && decodableBytes.length / bytes.length > maxInflationRatio) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Payload inflation ratio exceeds allowed maximum',
            context: {
              'decodedSize': decodableBytes.length,
              'compressedSize': bytes.length,
              'maxInflationRatio': maxInflationRatio,
            },
          ),
        );
      }

      final Object decoded;
      if (frame.enc == 'json' && decodableBytes.length >= jsonPayloadIsolateEncodeThresholdBytes) {
        try {
          decoded = await compute(
            _jsonDecodeUtf8PayloadInIsolate,
            decodableBytes,
          );
        } on Object catch (error) {
          return Failure(
            domain.PayloadEncodingFailure.withContext(
              message: 'Failed to decode JSON payload',
              cause: error,
              context: {'operation': 'jsonDecode', 'encoding': 'json'},
            ),
          );
        }
      } else {
        final codec = PayloadCodecFactory.getCodec(frame.enc);
        final decodeResult = codec.decode(decodableBytes);

        if (decodeResult.isError()) {
          return Failure(decodeResult.exceptionOrNull()!);
        }

        decoded = decodeResult.getOrThrow() as Object;
      }

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
