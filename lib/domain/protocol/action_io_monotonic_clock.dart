/// Process-local time, independent of Windows/NTP wall-clock corrections.
abstract final class ActionIoMonotonicClock {
  static final Stopwatch _clock = Stopwatch()..start();
  static int nowMs() => _clock.elapsedMilliseconds;
}
