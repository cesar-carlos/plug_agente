import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/adaptive_compression_cache.dart';

void main() {
  group('AdaptiveCompressionCache', () {
    test('skips only the same event and size tier after an ineffective attempt', () {
      var now = DateTime.utc(2026);
      final cache = AdaptiveCompressionCache(
        ttl: const Duration(seconds: 11),
        now: () => now,
      );

      cache.recordAttempt(eventName: 'rpc:response', originalSize: 8192, reduced: false);

      expect(cache.shouldSkip(eventName: 'rpc:response', originalSize: 9000), isTrue);
      expect(cache.shouldSkip(eventName: 'rpc:chunk', originalSize: 9000), isFalse);
      now = now.add(const Duration(seconds: 11));
      expect(cache.shouldSkip(eventName: 'rpc:response', originalSize: 9000), isFalse);
    });

    test('a successful compression clears the negative decision', () {
      final cache = AdaptiveCompressionCache();
      cache.recordAttempt(eventName: 'rpc:response', originalSize: 4096, reduced: false);
      cache.recordAttempt(eventName: 'rpc:response', originalSize: 4096, reduced: true);

      expect(cache.shouldSkip(eventName: 'rpc:response', originalSize: 4096), isFalse);
    });
  });
}
