import 'dart:math';

/// Computes reconnect delay with exponential backoff and optional jitter.
///
/// Used by the app-level connection recovery flow (`ConnectionProvider`).
/// Jitter (±15% by default) helps avoid thundering herd when many
/// clients reconnect after an outage.
Duration computeReconnectDelay({
  required int attempt,
  required Duration initialDelay,
  required Duration maxDelay,
  double jitterFraction = 0.15,
  Random? random,
}) {
  final attemptOffset = attempt - 1;
  final safeExponent = attemptOffset < 0 ? 0 : (attemptOffset > 5 ? 5 : attemptOffset);
  final multiplier = 1 << safeExponent;
  final seconds = initialDelay.inSeconds * multiplier;
  final cappedSeconds = seconds > maxDelay.inSeconds ? maxDelay.inSeconds : seconds;
  final baseMs = cappedSeconds * 1000;
  final rng = random ?? Random();
  final jitterFactor = (rng.nextDouble() * 2 - 1) * jitterFraction;
  final jitteredMs = (baseMs * (1 + jitterFactor)).round();
  final safeMs = jitteredMs < 100 ? 100 : jitteredMs;
  return Duration(milliseconds: safeMs);
}
