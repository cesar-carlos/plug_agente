import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:result_dart/result_dart.dart';
import '../../domain/errors/failures.dart' as domain;

class GzipCompressor {
  Future<Result<List<Map<String, dynamic>>>> compress(
    List<Map<String, dynamic>> data,
  ) async {
    try {
      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      final compressedBytes = GZipEncoder().encode(bytes);

      if (compressedBytes == null) {
        return Failure(
          domain.CompressionFailure('Failed to compress data: encoder returned null'),
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
    } catch (e) {
      return Failure(
        domain.CompressionFailure('Failed to compress data: $e'),
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
          List<Map<String, dynamic>>.from(jsonDecode(jsonString)),
        );
      }

      // Return data as-is if not compressed
      return Success(data);
    } catch (e) {
      return Failure(
        domain.CompressionFailure('Failed to decompress data: $e'),
      );
    }
  }
}
