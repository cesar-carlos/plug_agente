import 'dart:math';

class AgentActionRemoteRateLimitDecision {
  const AgentActionRemoteRateLimitDecision({
    required this.allowed,
    required this.retryAfter,
  });

  final bool allowed;
  final Duration? retryAfter;
}

class AgentActionRemoteRateLimiter {
  AgentActionRemoteRateLimiter({
    required int maxCallsPerMinute,
    int maxScopeEntries = 8192,
    Random? random,
    DateTime Function()? now,
  }) : _max = maxCallsPerMinute,
       _maxScopeEntries = maxScopeEntries,
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  final int _max;
  final int _maxScopeEntries;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, _WindowCount> _windows = <String, _WindowCount>{};

  int get trackedScopeCount => _windows.length;

  AgentActionRemoteRateLimitDecision tryAcquire({
    required String agentId,
    required String method,
    required String actionId,
    required String requesterKey,
  }) {
    if (_max <= 0) {
      return const AgentActionRemoteRateLimitDecision(
        allowed: true,
        retryAfter: null,
      );
    }

    final now = _now().toUtc();
    final windowId = _windowId(now);
    final scopeKey = _scopeKey(
      agentId: agentId,
      method: method,
      actionId: actionId,
      requesterKey: requesterKey,
    );
    final entry = _windows[scopeKey];
    if (entry == null || entry.windowId != windowId) {
      if (entry == null) {
        _evictBeforeNewKeyIfNeeded(windowId);
      }
      _windows[scopeKey] = _WindowCount(windowId, 1);
      _trimExcessEntries(windowId);
      return const AgentActionRemoteRateLimitDecision(
        allowed: true,
        retryAfter: null,
      );
    }

    if (entry.count >= _max) {
      return AgentActionRemoteRateLimitDecision(
        allowed: false,
        retryAfter: Duration(
          milliseconds: (windowId + 1) * 60000 - now.millisecondsSinceEpoch,
        ),
      );
    }

    entry.count++;
    return const AgentActionRemoteRateLimitDecision(
      allowed: true,
      retryAfter: null,
    );
  }

  String _scopeKey({
    required String agentId,
    required String method,
    required String actionId,
    required String requesterKey,
  }) {
    return '$agentId|$method|$actionId|$requesterKey';
  }

  void _evictBeforeNewKeyIfNeeded(int currentWindowId) {
    if (_maxScopeEntries <= 0 || _windows.length < _maxScopeEntries) {
      return;
    }
    _windows.removeWhere((_, _WindowCount value) => value.windowId < currentWindowId - 2);
    while (_maxScopeEntries > 0 && _windows.length >= _maxScopeEntries && _windows.isNotEmpty) {
      final keys = _windows.keys.toList(growable: false);
      _windows.remove(keys[_random.nextInt(keys.length)]);
    }
  }

  void _trimExcessEntries(int currentWindowId) {
    if (_windows.length <= 4096) {
      return;
    }
    _windows.removeWhere((_, _WindowCount value) => value.windowId < currentWindowId - 2);
  }

  int _windowId(DateTime now) => now.millisecondsSinceEpoch ~/ 60000;
}

class _WindowCount {
  _WindowCount(this.windowId, this.count);

  final int windowId;
  int count;
}
