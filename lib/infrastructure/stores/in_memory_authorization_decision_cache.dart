import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';

class InMemoryAuthorizationDecisionCache implements IAuthorizationDecisionCache {
  final Map<String, AuthorizationDecisionCacheEntry> _entries = <String, AuthorizationDecisionCacheEntry>{};

  @override
  AuthorizationDecisionCacheEntry? get(String key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  @override
  void put(String key, AuthorizationDecisionCacheEntry entry) {
    _entries[key] = entry;
  }

  @override
  void invalidate(String key) {
    _entries.remove(key);
  }

  @override
  void invalidateAll() {
    _entries.clear();
  }
}
