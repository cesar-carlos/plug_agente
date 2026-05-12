typedef LogRateLimiterClock = DateTime Function();

class LogRateLimiter {
  LogRateLimiter({
    this.initialBurst = 4,
    this.stride = 16,
    this.minimumInterval,
    LogRateLimiterClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final int initialBurst;
  final int stride;
  final Duration? minimumInterval;
  final LogRateLimiterClock _clock;
  final Map<String, _LogRateLimitState> _states = <String, _LogRateLimitState>{};

  bool shouldLog(String category) {
    final state = _states.putIfAbsent(category, _LogRateLimitState.new);
    state.count++;

    final countAllows = state.count <= initialBurst || (stride > 0 && state.count % stride == 0);
    if (!countAllows) {
      return false;
    }

    final interval = minimumInterval;
    if (interval == null) {
      state.lastLoggedAt = _clock();
      return true;
    }

    final now = _clock();
    final last = state.lastLoggedAt;
    if (last != null && now.difference(last) < interval) {
      return false;
    }
    state.lastLoggedAt = now;
    return true;
  }

  int countFor(String category) => _states[category]?.count ?? 0;

  void reset([String? category]) {
    if (category == null) {
      _states.clear();
      return;
    }
    _states.remove(category);
  }
}

class _LogRateLimitState {
  int count = 0;
  DateTime? lastLoggedAt;
}
