import 'dart:io';
import 'dart:typed_data';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Converts VM gzip encode/decode output to [Uint8List] without copying when
/// the result is already a [Uint8List].
Uint8List _listToUint8List(List<int> bytes) {
  if (bytes.isEmpty) {
    return Uint8List(0);
  }
  if (bytes is Uint8List) {
    return bytes;
  }
  return Uint8List.fromList(bytes);
}

/// Shared GZIP byte primitives for codecs, transport pipeline isolates, and
/// row-level gzip in `gzip_compressor.dart`. Uses VM `dart:io` gzip (zlib),
/// not `package:archive`.
Uint8List gzipCompressBytesOrThrow(Uint8List data) {
  final encoded = gzip.encode(data);
  return _listToUint8List(encoded);
}

/// Decompresses a GZIP byte stream; throws if the input is not valid GZIP.
Uint8List gzipDecompressBytesOrThrow(Uint8List compressed) {
  final decoded = gzip.decode(compressed);
  return _listToUint8List(decoded);
}

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
      return Success(gzipCompressBytesOrThrow(data));
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

  @override
  Result<Uint8List> decompress(Uint8List data) {
    try {
      return Success(gzipDecompressBytesOrThrow(data));
    } on Object catch (error) {
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
