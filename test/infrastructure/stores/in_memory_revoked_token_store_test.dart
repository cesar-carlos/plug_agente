import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';

void main() {
  group('InMemoryRevokedTokenStore', () {
    test('should return false when token not added', () {
      final store = InMemoryRevokedTokenStore();
      expect(store.isRevoked('token-123'), isFalse);
    });

    test('should return true after token is added', () {
      final store = InMemoryRevokedTokenStore();
      store.add('token-123');
      expect(store.isRevoked('token-123'), isTrue);
    });

    test('should return false for different token', () {
      final store = InMemoryRevokedTokenStore();
      store.add('token-123');
      expect(store.isRevoked('token-456'), isFalse);
    });

    test('should expire after TTL', () {
      var now = DateTime(2026, 1, 1, 12);
      final store = InMemoryRevokedTokenStore(
        defaultTtl: const Duration(seconds: 1),
        nowProvider: () => now,
      );
      store.add('token-123');
      expect(store.isRevoked('token-123'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(store.isRevoked('token-123'), isFalse);
    });
  });
}
