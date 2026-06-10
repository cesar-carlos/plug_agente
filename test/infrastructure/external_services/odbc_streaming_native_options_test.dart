import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';

void main() {
  group('OdbcStreamingNativeOptions.resolve', () {
    test('should clamp fetch size and native chunk bytes', () {
      final options = OdbcStreamingNativeOptions.resolve(
        fetchSize: 250,
        chunkSizeBytes: 32 * 1024,
        settingsMaxResultBufferMb: 16,
      );

      expect(options.fetchSize, 250);
      expect(
        options.nativeChunkSizeBytes,
        OdbcStreamingNativeOptions.minNativeChunkSizeBytes,
      );
      expect(options.maxResultBufferBytes, greaterThanOrEqualTo(16 * 1024 * 1024));
    });

    test('should fall back to default fetch size when non-positive', () {
      final options = OdbcStreamingNativeOptions.resolve(
        fetchSize: 0,
        chunkSizeBytes: 128 * 1024,
        settingsMaxResultBufferMb: 16,
      );

      expect(options.fetchSize, OdbcStreamingNativeOptions.odbcFastDefaultFetchSize);
      expect(options.nativeChunkSizeBytes, 128 * 1024);
    });
  });
}
