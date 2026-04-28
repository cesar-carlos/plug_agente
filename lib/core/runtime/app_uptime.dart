/// Wall-clock start time for the current process, used by health and diagnostics.
///
/// Call [markStarted] once during bootstrap; before that, [uptimeSeconds] is zero.
final class AppUptime {
  AppUptime._();

  static DateTime? _startedAt;

  /// Records the start instant if not already set (idempotent).
  static void markStarted() {
    _startedAt ??= DateTime.now();
  }

  /// Seconds since [markStarted], or `0` if not marked yet.
  static int get uptimeSeconds {
    final start = _startedAt;
    if (start == null) {
      return 0;
    }
    return DateTime.now().difference(start).inSeconds;
  }
}
