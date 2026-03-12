import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';

void main() {
  group('GzipCompressionCodec', () {
    late GzipCompressionCodec codec;

    setUp(() {
      codec = const GzipCompressionCodec();
    });

    test('should compress data successfully', () {
      final data = Uint8List.fromList(utf8.encode('Hello World! ' * 100));

      final result = codec.compress(data);

      expect(result.isSuccess(), isTrue);
      final compressed = result.getOrThrow();
      expect(compressed.length, lessThan(data.length));
    });

    test('should decompress data successfully', () {
      final original = Uint8List.fromList(utf8.encode('Hello World! ' * 100));
      final compressed = codec.compress(original).getOrThrow();

      final result = codec.decompress(compressed);

      expect(result.isSuccess(), isTrue);
      final decompressed = result.getOrThrow();
      expect(decompressed, equals(original));
    });

    test('should handle round-trip compression and decompression', () {
      final original = Uint8List.fromList(
        utf8.encode(jsonEncode({'data': 'test' * 1000})),
      );

      final compressResult = codec.compress(original);
      expect(compressResult.isSuccess(), isTrue);

      final decompressResult = codec.decompress(compressResult.getOrThrow());
      expect(decompressResult.isSuccess(), isTrue);

      expect(decompressResult.getOrThrow(), equals(original));
    });

    test('should return failure when decompressing invalid data', () {
      final invalidData = Uint8List.fromList([1, 2, 3, 4]);

      final result = codec.decompress(invalidData);

      expect(result.isError(), isTrue);
    });

    test('should have correct algorithm name', () {
      expect(codec.algorithm, equals('gzip'));
    });
  });

  group('NoCompressionCodec', () {
    late NoCompressionCodec codec;

    setUp(() {
      codec = const NoCompressionCodec();
    });

    test('should return data unchanged on compress', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);

      final result = codec.compress(data);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(data));
    });

    test('should return data unchanged on decompress', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);

      final result = codec.decompress(data);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(data));
    });

    test('should have correct algorithm name', () {
      expect(codec.algorithm, equals('none'));
    });
  });

  group('CompressionCodecFactory', () {
    test('should return GzipCompressionCodec for gzip', () {
      final codec = CompressionCodecFactory.getCodec('gzip');

      expect(codec, isA<GzipCompressionCodec>());
    });

    test('should return NoCompressionCodec for none', () {
      final codec = CompressionCodecFactory.getCodec('none');

      expect(codec, isA<NoCompressionCodec>());
    });

    test('should throw ArgumentError for unsupported algorithm', () {
      expect(
        () => CompressionCodecFactory.getCodec('invalid'),
        throwsArgumentError,
      );
    });
  });
}
