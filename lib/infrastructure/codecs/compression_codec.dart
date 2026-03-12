import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Codec for compressing and decompressing data.
abstract class ICompressionCodec {
  /// Compresses bytes.
  Result<Uint8List> compress(Uint8List data);

  /// Decompresses bytes.
  Result<Uint8List> decompress(Uint8List data);

  /// Returns the compression algorithm name.
  String get algorithm;
}

/// GZIP compression codec.
class GzipCompressionCodec implements ICompressionCodec {
  const GzipCompressionCodec();

  @override
  String get algorithm => 'gzip';

  @override
  Result<Uint8List> compress(Uint8List data) {
    try {
      final compressedBytes = GZipEncoder().encode(data);

      if (compressedBytes == null) {
        return Failure(
          domain.CompressionFailure.withContext(
            message: 'GZIP encoder returned null',
            context: {'operation': 'compress', 'algorithm': 'gzip'},
          ),
        );
      }

      return Success(Uint8List.fromList(compressedBytes));
    } on Exception catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to compress with GZIP',
          cause: error,
          context: {'operation': 'compress', 'algorithm': 'gzip'},
        ),
      );
    }
  }

  @override
  Result<Uint8List> decompress(Uint8List data) {
    try {
      final decompressedBytes = GZipDecoder().decodeBytes(data);
      return Success(Uint8List.fromList(decompressedBytes));
    } on Exception catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to decompress with GZIP',
          cause: error,
          context: {'operation': 'decompress', 'algorithm': 'gzip'},
        ),
      );
    }
  }
}

/// No-op compression codec (passthrough).
class NoCompressionCodec implements ICompressionCodec {
  const NoCompressionCodec();

  @override
  String get algorithm => 'none';

  @override
  Result<Uint8List> compress(Uint8List data) {
    return Success(data);
  }

  @override
  Result<Uint8List> decompress(Uint8List data) {
    return Success(data);
  }
}

/// Factory for creating compression codecs.
class CompressionCodecFactory {
  static ICompressionCodec getCodec(String algorithm) {
    return switch (algorithm) {
      'gzip' => const GzipCompressionCodec(),
      'none' => const NoCompressionCodec(),
      _ => throw ArgumentError('Unsupported compression: $algorithm'),
    };
  }
}
