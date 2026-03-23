import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';

void main() {
  group('InMemoryAuthorizationDecisionCache', () {
    test('invalidateForCredentialHash removes all keys for that credential', () {
      final cache = InMemoryAuthorizationDecisionCache(maxEntries: 100);
      final expires = DateTime.now().add(const Duration(minutes: 1));
      final entry = AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: expires,
      );

      cache.put('credA|op1|res1', entry);
      cache.put('credA|op2|res2', entry);
      cache.put('credB|op1|res1', entry);

      cache.invalidateForCredentialHash('credA');

      check(cache.get('credA|op1|res1')).isNull();
      check(cache.get('credA|op2|res2')).isNull();
      check(cache.get('credB|op1|res1')).isNotNull();
    });

    test('eviction keeps credential index consistent', () {
      final cache = InMemoryAuthorizationDecisionCache(maxEntries: 2);
      final expires = DateTime.now().add(const Duration(minutes: 1));
      final entry = AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: expires,
      );

      cache.put('h1|a|x', entry);
      cache.put('h1|b|y', entry);
      cache.put('h1|c|z', entry);

      cache.invalidateForCredentialHash('h1');

      check(cache.get('h1|a|x')).isNull();
      check(cache.get('h1|b|y')).isNull();
      check(cache.get('h1|c|z')).isNull();
    });

    test('get drops expired entry and clears credential index', () {
      final cache = InMemoryAuthorizationDecisionCache();
      final past = DateTime.now().subtract(const Duration(seconds: 1));
      final entry = AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: past,
      );

      cache.put('hx|op|r', entry);
      check(cache.get('hx|op|r')).isNull();

      cache.put('hx|op|r2', AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      ));
      cache.invalidateForCredentialHash('hx');
      check(cache.get('hx|op|r2')).isNull();
    });
  });
}
