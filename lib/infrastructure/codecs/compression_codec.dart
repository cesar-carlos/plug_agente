import 'dart:io' show GZipCodec, gzip;
import 'dart:typed_data';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Zlib best-speed level (same idea as `Z_BEST_SPEED`); used for Socket.IO
/// outbound gzip only — row compression keeps the default level.
const int gzipTransportZlibLevel = 1;

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
///
/// When [compressionLevel] is null, uses zlib default (balanced). Row payloads
/// keep the default; Socket.IO transport uses [gzipTransportZlibLevel].
Uint8List gzipCompressBytesOrThrow(
  Uint8List data, {
  int? compressionLevel,
}) {
  final List<int> encoded;
  if (compressionLevel == null) {
    encoded = gzip.encode(data);
  } else {
    encoded = GZipCodec(level: compressionLevel).encode(data);
  }
  return _listToUint8List(encoded);
}

/// Bundle for Flutter `compute` when zlib level must match outbound pipeline.
typedef GzipCompressIsolateArgs = (Uint8List bytes, int level);

Uint8List gzipCompressWithLevelForIsolate(GzipCompressIsolateArgs args) =>
    gzipCompressBytesOrThrow(args.$1, compressionLevel: args.$2);

/// Top-level for `compute` using [gzipTransportZlibLevel] (default fast outbound).
Uint8List gzipCompressTransportBytesForIsolate(Uint8List data) =>
    gzipCompressWithLevelForIsolate((data, gzipTransportZlibLevel));

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
  const GzipCompressionCodec({this.compressionLevel});

  /// When null, uses zlib default (row payloads and general use).
  final int? compressionLevel;

  /// Outbound Socket.IO / transport pipeline frames: lower CPU, often larger
  /// wire size than default level.
  static const GzipCompressionCodec transport = GzipCompressionCodec(
    compressionLevel: gzipTransportZlibLevel,
  );

  @override
  String get algorithm => 'gzip';

  @override
  Result<Uint8List> compress(Uint8List data) {
    try {
      return Success(
        gzipCompressBytesOrThrow(
          data,
          compressionLevel: compressionLevel,
        ),
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
