import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';

void main() {
  group('InMemoryAuthorizationDecisionCache', () {
    AuthorizationDecisionCacheEntry entry({
      required String keySuffix,
      Duration ttl = const Duration(minutes: 1),
    }) {
      return AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: DateTime.now().add(ttl),
        clientId: 'c1',
        reason: keySuffix,
      );
    }

    test('get returns null for missing key', () {
      final cache = InMemoryAuthorizationDecisionCache();
      expect(cache.get('missing'), isNull);
    });

    test('get returns null for expired entry', () {
      final cache = InMemoryAuthorizationDecisionCache();
      cache.put(
        'k1',
        AuthorizationDecisionCacheEntry(
          allowed: true,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      expect(cache.get('k1'), isNull);
    });

    test('put and get returns entry and refreshes recency', () {
      final cache = InMemoryAuthorizationDecisionCache(maxEntries: 10);
      cache.put('a', entry(keySuffix: 'a'));
      cache.put('b', entry(keySuffix: 'b'));

      final got = cache.get('a');
      expect(got, isNotNull);
      expect(got!.reason, 'a');

      cache.put('c', entry(keySuffix: 'c'));
      expect(cache.get('a'), isNotNull);
    });

    test('evicts oldest when over maxEntries', () {
      final cache = InMemoryAuthorizationDecisionCache(maxEntries: 2);
      cache.put('x1', entry(keySuffix: '1'));
      cache.put('x2', entry(keySuffix: '2'));
      cache.put('x3', entry(keySuffix: '3'));

      expect(cache.get('x1'), isNull);
      expect(cache.get('x2'), isNotNull);
      expect(cache.get('x3'), isNotNull);
    });

    test('invalidate removes key', () {
      final cache = InMemoryAuthorizationDecisionCache();
      cache.put('k', entry(keySuffix: 'k'));
      cache.invalidate('k');
      expect(cache.get('k'), isNull);
    });

    test('invalidateForCredentialHash removes keys with prefix', () {
      final cache = InMemoryAuthorizationDecisionCache();
      const hash = 'abc123';
      cache.put('$hash|1', entry(keySuffix: '1'));
      cache.put('$hash|2', entry(keySuffix: '2'));
      cache.put('other|1', entry(keySuffix: 'o'));

      cache.invalidateForCredentialHash(hash);

      expect(cache.get('$hash|1'), isNull);
      expect(cache.get('$hash|2'), isNull);
      expect(cache.get('other|1'), isNotNull);
    });

    test('invalidateAll clears cache', () {
      final cache = InMemoryAuthorizationDecisionCache();
      cache.put('a', entry(keySuffix: 'a'));
      cache.invalidateAll();
      expect(cache.get('a'), isNull);
    });
  });
}
