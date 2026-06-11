import 'dart:math';

/// Policy bundle used by the auto-update flow for any "try N times,
/// back off with jitter between attempts" loop. Replaces the previous
/// model of passing `attemptLimit`, `baseDelay`, `jitterFactor`,
/// `random` and `triggerTimeout` as five independent constructor
/// parameters on the orchestrator.
///
/// Keep the policy immutable; tests can construct a deterministic
/// instance by passing a seeded [Random].
class RetryPolicy {
  RetryPolicy({
    required this.attemptLimit,
    required this.baseDelay,
    required this.triggerTimeout,
    this.jitterFactor = 0,
    Random? random,
  }) : assert(attemptLimit > 0, 'attemptLimit must be positive'),
       assert(jitterFactor >= 0 && jitterFactor <= 1, 'jitterFactor must be in [0, 1]'),
       // Default to `Random.secure()` so the jitter source matches the
       // rollout bucket selector and a fleet sharing the same boot
       // moment cannot accidentally synchronise retries because every
       // agent seeded the cheap `Random()` from the same `DateTime.now()`.
       // Tests can still inject a deterministic seeded `Random` via
       // the [random] parameter.
       _random = random ?? Random.secure();

  /// Maximum number of attempts (`attempt` runs from 1..[attemptLimit]).
  final int attemptLimit;

  /// Base delay multiplier. The delay before the next retry is
  /// `baseDelay * attempt` (linear back-off) before jitter.
  final Duration baseDelay;

  /// Maximum wall-clock window for each single trigger; the caller
  /// times its async work out at this value before counting the
  /// attempt as failed.
  final Duration triggerTimeout;

  /// Symmetric jitter applied to the linear back-off as
  /// `delay ± delay * jitterFactor`. `0` disables jitter.
  final double jitterFactor;

  final Random _random;

  /// Computes the wait time before the next retry attempt. Returns at
  /// least 100ms so the event loop always yields between attempts.
  Duration delayBeforeAttempt(int attempt) {
    final baseMs = (baseDelay * attempt).inMilliseconds;
    if (jitterFactor == 0 || baseMs <= 0) {
      return Duration(milliseconds: baseMs);
    }
    final span = baseMs * jitterFactor;
    final offset = (_random.nextDouble() * 2 - 1) * span;
    final jitteredMs = (baseMs + offset).round();
    return Duration(milliseconds: jitteredMs < 100 ? 100 : jitteredMs);
  }
}
