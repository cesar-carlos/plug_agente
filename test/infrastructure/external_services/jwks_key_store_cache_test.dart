import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:plug_agente/infrastructure/external_services/jwks_key_store_cache.dart';

void main() {
  group('JwksKeyStoreCache', () {
    test('explicit trust invalidation discards a remembered store for the same URL', () {
      final cache = JwksKeyStoreCache(jwksCacheTtl: const Duration(minutes: 5), now: () => DateTime.utc(2026));
      const url = 'https://example.com/jwks.json';
      final first = cache.resolve(url).getOrThrow();
      cache.remember(url, first);
      cache.invalidate();
      expect(cache.resolve(url).getOrThrow(), isNot(same(first)));
    });

    test('should reuse store when cache is valid after remember', () {
      var factoryCalls = 0;
      final now = DateTime.utc(2026);
      final cache = JwksKeyStoreCache(
        jwksCacheTtl: const Duration(minutes: 5),
        now: () => now,
        createKeyStore: (u) {
          factoryCalls++;
          return JsonWebKeyStore()..addKeySetUrl(u);
        },
      );

      const url = 'https://example.com/jwks.json';
      final first = cache.resolve(url).getOrThrow();
      cache.remember(url, first);
      final second = cache.resolve(url).getOrThrow();

      expect(identical(first, second), isTrue);
      expect(factoryCalls, 1);
    });

    test('should create new store after TTL expires', () {
      var factoryCalls = 0;
      final clock = <DateTime>[DateTime.utc(2026)];
      final cache = JwksKeyStoreCache(
        jwksCacheTtl: const Duration(minutes: 5),
        now: () => clock[0],
        createKeyStore: (u) {
          factoryCalls++;
          return JsonWebKeyStore()..addKeySetUrl(u);
        },
      );

      const url = 'https://example.com/jwks.json';
      final first = cache.resolve(url).getOrThrow();
      cache.remember(url, first);
      clock[0] = clock[0].add(const Duration(minutes: 6));
      final afterExpiry = cache.resolve(url).getOrThrow();

      expect(identical(first, afterExpiry), isFalse);
      expect(factoryCalls, 2);
    });

    test('should invalidate cache when JWKS URL changes', () {
      var factoryCalls = 0;
      final now = DateTime.utc(2026);
      final cache = JwksKeyStoreCache(
        jwksCacheTtl: const Duration(minutes: 5),
        now: () => now,
        createKeyStore: (u) {
          factoryCalls++;
          return JsonWebKeyStore()..addKeySetUrl(u);
        },
      );

      final a = cache.resolve('https://a.example/jwks.json').getOrThrow();
      cache.remember('https://a.example/jwks.json', a);
      final b = cache.resolve('https://b.example/jwks.json').getOrThrow();

      expect(factoryCalls, 2);
      expect(identical(a, b), isFalse);
    });
  });
}
