import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/compression/gzip_compressor.dart';

void main() {
  group('GzipCompressor', () {
    test('should compress and decompress round-trip without double JSON encode', () async {
      final compressor = GzipCompressor();
      final rows = List<Map<String, dynamic>>.generate(
        400,
        (int i) => <String, dynamic>{'n': i, 't': 'x' * 20},
      );

      final compressed = await compressor.compress(rows);
      expect(compressed.isSuccess(), isTrue);

      final decompressed = await compressor.decompress(compressed.getOrNull()!);
      expect(decompressed.isSuccess(), isTrue);
      expect(decompressed.getOrNull(), rows);
    });
  });
}
