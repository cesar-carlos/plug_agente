import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_compressor.dart';
import 'package:result_dart/result_dart.dart';

List<Map<String, dynamic>> _compressInIsolate(List<Map<String, dynamic>> data) {
  final jsonString = jsonEncode(data);
  final bytes = utf8.encode(jsonString);
  final compressedBytes = GZipEncoder().encode(bytes);

  if (compressedBytes == null) {
    throw StateError('GZipEncoder returned null');
  }

  final base64String = base64.encode(compressedBytes);
  return [
    {
      'compressed_data': base64String,
      'is_compressed': true,
      'original_size': bytes.length,
    },
  ];
}

List<Map<String, dynamic>> _decompressInIsolate(
  List<Map<String, dynamic>> data,
) {
  if (data.length != 1 || !data.first.containsKey('compressed_data') || data.first['is_compressed'] != true) {
    return data;
  }

  final base64String = data.first['compressed_data'] as String;
  final compressedBytes = base64.decode(base64String);
  final decompressedBytes = GZipDecoder().decodeBytes(compressedBytes);
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
      final result = await compute(_compressInIsolate, data);
      return Success(result);
    } on Exception catch (error) {
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
      final result = await compute(_decompressInIsolate, data);
      return Success(result);
    } on Exception catch (error) {
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
