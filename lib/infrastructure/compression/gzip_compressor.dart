import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// Top-level for [compute]: pass JSON text so the caller isolate does not
/// [jsonEncode] twice.
List<Map<String, dynamic>> _compressFromJsonString(String jsonString) {
  return _wrapperFromPlainUtf8Bytes(utf8.encode(jsonString));
}

List<Map<String, dynamic>> _decompressRows(List<Map<String, dynamic>> data) {
  if (data.length != 1 || !data.first.containsKey('compressed_data') || data.first['is_compressed'] != true) {
    return data;
  }

  final base64String = data.first['compressed_data'] as String;
  final compressedBytes = base64Decode(base64String);
  final decompressedBytes = gzipDecompressBytesOrThrow(compressedBytes);
  final jsonString = utf8.decode(decompressedBytes);

  return List<Map<String, dynamic>>.from(
    jsonDecode(jsonString) as Iterable<dynamic>,
  );
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
      final jsonString = jsonEncode(data);
      final plainBytes = utf8.encode(jsonString);
      if (plainBytes.length <= gzipRowComputeMinUtf8Bytes) {
        return Success(_wrapperFromPlainUtf8Bytes(plainBytes));
      }
      final result = await compute(_compressFromJsonString, jsonString);
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
