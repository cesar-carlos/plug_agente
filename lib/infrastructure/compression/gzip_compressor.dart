import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class GzipCompressor {
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

  Future<Result<List<Map<String, dynamic>>>> compress(
    List<Map<String, dynamic>> data,
  ) async {
    try {
      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      final compressedBytes = GZipEncoder().encode(bytes);

      if (compressedBytes == null) {
        return Failure(
          _buildFailure(
            'Failed to compress data',
            context: {'reason': 'encoder_returned_null'},
          ),
        );
      }

      // Convert compressed bytes back to base64 string for JSON compatibility
      final base64String = base64.encode(compressedBytes);

      return Success([
        {
          'compressed_data': base64String,
          'is_compressed': true,
          'original_size': bytes.length,
        },
      ]);
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

  Future<Result<List<Map<String, dynamic>>>> decompress(
    List<Map<String, dynamic>> data,
  ) async {
    try {
      // Check if data is compressed
      if (data.length == 1 &&
          data.first.containsKey('compressed_data') &&
          data.first['is_compressed'] == true) {
        final base64String = data.first['compressed_data'] as String;
        final compressedBytes = base64.decode(base64String);
        final decompressedBytes = GZipDecoder().decodeBytes(compressedBytes);
        final jsonString = utf8.decode(decompressedBytes);

        return Success(
          List<Map<String, dynamic>>.from(
            jsonDecode(jsonString) as Iterable<dynamic>,
          ),
        );
      }

      // Return data as-is if not compressed
      return Success(data);
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
