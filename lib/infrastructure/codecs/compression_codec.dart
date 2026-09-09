import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Codec for compressing and decompressing data.
abstract class ICompressionCodec {
  /// Compresses bytes.
  Result<Uint8List> compress(Uint8List data);

  /// Decompresses bytes.
  Result<Uint8List> decompress(
    Uint8List data, {
    required int maxOutputBytes,
  });

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
      final compressedBytes = const GZipEncoder().encode(data);
      return Success(Uint8List.fromList(compressedBytes));
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
  Result<Uint8List> decompress(
    Uint8List data, {
    required int maxOutputBytes,
  }) {
    try {
      return Success(decompressGzipBytesBounded(data, maxOutputBytes));
    } on Object catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to decompress with GZIP',
          cause: error,
          context: {
            'operation': 'decompress',
            'algorithm': 'gzip',
            'max_output_bytes': maxOutputBytes,
          },
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
  Result<Uint8List> decompress(
    Uint8List data, {
    required int maxOutputBytes,
  }) {
    if (data.length > maxOutputBytes) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Decompressed payload exceeds configured limit',
          context: {
            'operation': 'decompress',
            'algorithm': 'none',
            'decoded_size': data.length,
            'max_output_bytes': maxOutputBytes,
          },
        ),
      );
    }
    return Success(data);
  }
}

/// Decompresses GZIP incrementally and fails before retaining more than
/// [maxOutputBytes]. `GZipDecoder.decodeBytes` materializes the complete
/// output before callers can validate it, which permits zip-bomb allocation.
Uint8List decompressGzipBytesBounded(Uint8List data, int maxOutputBytes) {
  if (maxOutputBytes < 0) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes', 'Must not be negative');
  }
  final output = _BoundedBytesSink(maxOutputBytes);
  final input = GZipCodec().decoder.startChunkedConversion(output);
  const chunkSize = 1024;
  for (var offset = 0; offset < data.length; offset += chunkSize) {
    final end = (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
    input.add(data.sublist(offset, end));
  }
  input.close();
  return output.takeBytes();
}

final class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this._maxOutputBytes);

  final int _maxOutputBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> chunk) {
    final nextLength = _length + chunk.length;
    if (nextLength > _maxOutputBytes) {
      throw StateError('GZIP output exceeds $_maxOutputBytes bytes');
    }
    _bytes.add(chunk);
    _length = nextLength;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
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
