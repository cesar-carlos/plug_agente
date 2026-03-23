import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_compressor.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:result_dart/result_dart.dart';

/// Below this UTF-8 JSON size, compress runs on the caller isolate (no
/// [compute]) to avoid isolate hop overhead for small row batches.
const int gzipRowComputeMinUtf8Bytes = 8192;

/// Below this compressed byte size (after base64 decode), decompress runs on
/// the caller isolate.
const int gzipRowComputeMinCompressedBytes = 8192;

/// Query/response row compression: JSON-encode rows, GZIP, then base64 in a map.
///
/// Distinct from PayloadFrame transport (`TransportPipeline` on Socket.IO).
List<Map<String, dynamic>> _wrapperFromPlainUtf8Bytes(Uint8List plainBytes) {
  final compressedBytes = gzipCompressBytesOrThrow(plainBytes);
  return [
    {
      'compressed_data': base64Encode(compressedBytes),
      'is_compressed': true,
      'original_size': plainBytes.length,
    },
  ];
}

/// Top-level for [compute]: JSON UTF-8 encode + gzip + base64 wrapper in one isolate.
List<Map<String, dynamic>> _compressJsonRowsInIsolate(
  List<Map<String, dynamic>> data,
) {
  final raw = JsonUtf8Encoder().convert(data);
  final plainBytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  return _wrapperFromPlainUtf8Bytes(plainBytes);
}

List<Map<String, dynamic>> _decompressRows(List<Map<String, dynamic>> data) {
  if (data.length != 1 || !data.first.containsKey('compressed_data') || data.first['is_compressed'] != true) {
    return data;
  }

  final base64String = data.first['compressed_data'] as String;
  final compressedBytes = base64Decode(base64String);
  final decompressedBytes = gzipDecompressBytesOrThrow(compressedBytes);
  final dynamic decoded = utf8.decoder.fuse(json.decoder).convert(decompressedBytes);
  return List<Map<String, dynamic>>.from(decoded as Iterable<dynamic>);
}

class GzipCompressor implements ICompressor {
  domain.CompressionFailure _buildFailure(
    String message, {
    Object? cause,
    Map<String, dynamic> context = const {},
  }) {
    return domain.CompressionFailure.withContext(
      message: message,
      cause: cause,
      context: context,
    );
  }

  @override
  Future<Result<List<Map<String, dynamic>>>> compress(
    List<Map<String, dynamic>> data,
  ) async {
    try {
      if (jsonTreeLikelyExceedsByteBudget(data, gzipRowComputeMinUtf8Bytes)) {
        final result = await compute(_compressJsonRowsInIsolate, data);
        return Success(result);
      }
      final raw = JsonUtf8Encoder().convert(data);
      final plainBytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
      if (plainBytes.length <= gzipRowComputeMinUtf8Bytes) {
        return Success(_wrapperFromPlainUtf8Bytes(plainBytes));
      }
      final result = await compute(_compressJsonRowsInIsolate, data);
      return Success(result);
    } on Object catch (error) {
      return Failure(
        _buildFailure(
          'Failed to compress data',
          cause: error,
          context: {'operation': 'compress'},
        ),
      );
    }
  }

  @override
  Future<Result<List<Map<String, dynamic>>>> decompress(
    List<Map<String, dynamic>> data,
  ) async {
    try {
      if (data.length != 1 || !data.first.containsKey('compressed_data') || data.first['is_compressed'] != true) {
        return Success(data);
      }
      final base64String = data.first['compressed_data'] as String;
      final compressedBytes = base64Decode(base64String);
      if (compressedBytes.length <= gzipRowComputeMinCompressedBytes) {
        return Success(_decompressRows(data));
      }
      final result = await compute(_decompressRows, data);
      return Success(result);
    } on Object catch (error) {
      return Failure(
        _buildFailure(
          'Failed to decompress data',
          cause: error,
          context: {'operation': 'decompress'},
        ),
      );
    }
  }
}
