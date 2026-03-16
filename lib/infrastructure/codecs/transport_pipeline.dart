import 'dart:typed_data';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Transport pipeline for encoding/compressing and decoding/decompressing payloads.
///
/// Handles the complete bidirectional flow:
/// Send: data -> encode -> compress -> frame
/// Receive: frame -> decompress -> decode -> data
class TransportPipeline {
  TransportPipeline({
    required this.encoding,
    required this.compression,
    this.compressionThreshold = 1024,
    this.schemaVersion = '1.0',
  });

  /// Selected encoding format.
  final String encoding;

  /// Selected compression algorithm.
  final String compression;

  /// Minimum payload size (bytes) to trigger compression.
  final int compressionThreshold;

  /// Schema version for the payload frame.
  final String schemaVersion;

  final _uuid = const Uuid();

  /// Prepares a payload for sending.
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

      // 2. Compress (if threshold met and compression enabled)
      final shouldCompress =
          compression != 'none' && originalSize >= compressionThreshold;

      Uint8List finalBytes;
      String finalCompression;
      int compressedSize;

      if (shouldCompress) {
        final compressionCodec = CompressionCodecFactory.getCodec(compression);
        final compressResult = compressionCodec.compress(encodedBytes);

        if (compressResult.isError()) {
          return Failure(compressResult.exceptionOrNull()!);
        }

        finalBytes = compressResult.getOrThrow();
        finalCompression = compression;
        compressedSize = finalBytes.length;
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
            message:
                'Frame encoding mismatch: expected $encoding, got ${frame.enc}',
            context: {'expected': encoding, 'actual': frame.enc},
          ),
        );
      }

      Uint8List bytes;

      // Ensure payload is bytes
      if (frame.payload is! Uint8List) {
        if (frame.payload is List<int>) {
          bytes = Uint8List.fromList(frame.payload as List<int>);
        } else {
          final payloadType = frame.payload.runtimeType.toString();
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'Frame payload is not binary data',
              context: {'payloadType': payloadType},
            ),
          );
        }
      } else {
        bytes = frame.payload as Uint8List;
      }

      if (bytes.length != frame.compressedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message:
                'Frame compressed size mismatch: expected ${frame.compressedSize}, got ${bytes.length}',
            context: {
              'expectedCompressedSize': frame.compressedSize,
              'actualCompressedSize': bytes.length,
            },
          ),
        );
      }
      if (maxCompressedBytes != null &&
          frame.compressedSize > maxCompressedBytes) {
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
            message:
                'Frame original size mismatch: expected ${frame.originalSize}, got ${decodableBytes.length}',
            context: {
              'expectedOriginalSize': frame.originalSize,
              'actualOriginalSize': decodableBytes.length,
            },
          ),
        );
      }
      if (maxOriginalBytes != null &&
          decodableBytes.length > maxOriginalBytes) {
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
      if (bytes.isNotEmpty &&
          decodableBytes.length / bytes.length > maxInflationRatio) {
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
