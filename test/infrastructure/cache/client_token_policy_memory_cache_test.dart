import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';

void main() {
  group('ClientTokenPolicyMemoryCache', () {
    ClientTokenPolicy policy(String id) {
      return ClientTokenPolicy(
        clientId: id,
        allTables: true,
        allViews: true,
        allPermissions: true,
        rules: const [],
      );
    }

    test('get returns null for unknown hash', () {
      final cache = ClientTokenPolicyMemoryCache();
      expect(cache.get('unknown'), isNull);
    });

    test('put and get returns policy', () {
      final cache = ClientTokenPolicyMemoryCache();
      final p = policy('c1');
      cache.put('h1', p);
      expect(cache.get('h1')?.clientId, 'c1');
    });

    test('expires entries after ttl', () async {
      final cache = ClientTokenPolicyMemoryCache(
        ttl: const Duration(milliseconds: 40),
        maxEntries: 100,
      );
      cache.put('h1', policy('c1'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cache.get('h1'), isNull);
    });

    test('evicts oldest when over maxEntries', () {
      final cache = ClientTokenPolicyMemoryCache(
        ttl: const Duration(hours: 1),
        maxEntries: 2,
      );
      cache.put('a', policy('a'));
      cache.put('b', policy('b'));
      cache.put('c', policy('c'));

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNotNull);
      expect(cache.get('c'), isNotNull);
    });

    test('invalidate removes entry', () {
      final cache = ClientTokenPolicyMemoryCache();
      cache.put('h', policy('c'));
      cache.invalidate('h');
      expect(cache.get('h'), isNull);
    });

    test('invalidateAll clears cache', () {
      final cache = ClientTokenPolicyMemoryCache();
      cache.put('h', policy('c'));
      cache.invalidateAll();
      expect(cache.get('h'), isNull);
    });
  });
}
