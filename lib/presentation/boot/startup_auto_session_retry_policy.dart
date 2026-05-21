import 'dart:math' as math;

import 'package:plug_agente/domain/errors/failures.dart';

class StartupAutoSessionRetryPolicy {
  const StartupAutoSessionRetryPolicy({
    this.maxTransientRetries = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
  }) : assert(
         maxTransientRetries >= 0,
         'maxTransientRetries must not be negative',
       );

  final int maxTransientRetries;
  final Duration initialDelay;
  final Duration maxDelay;

  bool canRetry(Object? failure, int completedTransientRetries) {
    return completedTransientRetries < maxTransientRetries && failure is Failure && failure.isTransient;
  }

  Duration delayForRetry(int retryNumber) {
    if (retryNumber <= 1) {
      return initialDelay;
    }

    final exponent = math.min(retryNumber - 1, 20);
    final multiplier = 1 << exponent;
    final delayMicros = initialDelay.inMicroseconds * multiplier;
    return Duration(
      microseconds: math.min(delayMicros, maxDelay.inMicroseconds),
    );
  }
}
