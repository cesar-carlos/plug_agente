import 'dart:math';

/// Fixed-window rate limiter for the client token getPolicy RPC (per agent + credential hash).
///
/// When max calls per minute is zero, tryAcquire always returns true.
///
/// When max scope entries is greater than zero, the number of distinct scope keys is capped:
/// before inserting a new key, stale windows are dropped and entries are evicted until under the cap.
/// Zero means no limit on distinct keys (only periodic trim of old windows when the map grows large).
class ClientTokenGetPolicyRateLimiter {
  ClientTokenGetPolicyRateLimiter({
    required int maxCallsPerMinute,
    int maxScopeEntries = 8192,
    Random? random,
  }) : _max = maxCallsPerMinute,
       _maxScopeEntries = maxScopeEntries,
       _random = random ?? Random.secure();

  final int _max;
  final int _maxScopeEntries;
  final Random _random;
  final Map<String, _WindowCount> _windows = <String, _WindowCount>{};

  /// Distinct scope keys currently tracked (for tests and diagnostics).
  int get trackedScopeCount => _windows.length;

  bool tryAcquire(String scopeKey) {
    if (_max <= 0) {
      return true;
    }
    final windowId = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000;
    final entry = _windows[scopeKey];
    if (entry == null || entry.windowId != windowId) {
      if (entry == null) {
        _evictBeforeNewKeyIfNeeded();
      }
      _windows[scopeKey] = _WindowCount(windowId, 1);
      _trimExcessEntries();
      return true;
    }
    if (entry.count >= _max) {
      return false;
    }
    entry.count++;
    return true;
  }

  void _evictBeforeNewKeyIfNeeded() {
    if (_maxScopeEntries <= 0 || _windows.length < _maxScopeEntries) {
      return;
    }
    _windows.removeWhere((_, _WindowCount value) => value.windowId < _currentWindowId() - 2);
    while (_maxScopeEntries > 0 && _windows.length >= _maxScopeEntries && _windows.isNotEmpty) {
      final keys = _windows.keys.toList();
      _windows.remove(keys[_random.nextInt(keys.length)]);
    }
  }

  void _trimExcessEntries() {
    if (_windows.length <= 4096) {
      return;
    }
    _windows.removeWhere((_, _WindowCount value) => value.windowId < _currentWindowId() - 2);
  }

  int _currentWindowId() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000;
}

class _WindowCount {
  _WindowCount(this.windowId, this.count);

  final int windowId;
  int count;
}
