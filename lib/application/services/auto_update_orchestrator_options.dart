import 'dart:math';

import 'package:plug_agente/application/services/retry_policy.dart';

/// Groups the orchestrator's policy knobs so the constructor stays
/// short and the call sites pass cohesive bundles instead of 25+
/// loose named arguments. The defaults match the previous inlined
/// values; tests can rebuild the bundle with `copyWith` to override
/// just the dimension they exercise.
class AutoUpdateOrchestratorOptions {
  AutoUpdateOrchestratorOptions({
    this.manualTriggerTimeout = const Duration(seconds: 15),
    this.manualCompletionTimeout = const Duration(seconds: 60),
    this.timeoutCircuitThreshold = 3,
    this.timeoutCircuitCooldown = const Duration(minutes: 15),
    this.lateCallbackDrainWindow = const Duration(seconds: 30),
    RetryPolicy? backgroundRetry,
    Random? random,
  }) : backgroundRetry =
           backgroundRetry ??
           RetryPolicy(
             attemptLimit: 3,
             baseDelay: const Duration(seconds: 30),
             triggerTimeout: const Duration(seconds: 30),
             jitterFactor: 0.2,
             random: random,
           );

  /// How long `checkManual` waits for the underlying
  /// `checkForUpdates(...)` trigger to return to Dart before timing
  /// out the attempt.
  final Duration manualTriggerTimeout;

  /// How long `checkManual` waits for the updater plugin's completion
  /// callback after the trigger returned.
  final Duration manualCompletionTimeout;

  /// Number of consecutive manual-check timeouts before the breaker
  /// opens. See `PersistentCircuitBreaker` for the underlying
  /// implementation.
  final int timeoutCircuitThreshold;

  /// How long the manual-check breaker stays open after tripping.
  final Duration timeoutCircuitCooldown;

  /// Window during which callbacks from a previously timed-out manual
  /// check are treated as late echoes and ignored, instead of
  /// polluting background diagnostics.
  final Duration lateCallbackDrainWindow;

  /// Retry policy for the background path. Encapsulates attempt
  /// limit, base delay, jitter and trigger timeout.
  final RetryPolicy backgroundRetry;

  AutoUpdateOrchestratorOptions copyWith({
    Duration? manualTriggerTimeout,
    Duration? manualCompletionTimeout,
    int? timeoutCircuitThreshold,
    Duration? timeoutCircuitCooldown,
    Duration? lateCallbackDrainWindow,
    RetryPolicy? backgroundRetry,
  }) {
    return AutoUpdateOrchestratorOptions(
      manualTriggerTimeout: manualTriggerTimeout ?? this.manualTriggerTimeout,
      manualCompletionTimeout: manualCompletionTimeout ?? this.manualCompletionTimeout,
      timeoutCircuitThreshold: timeoutCircuitThreshold ?? this.timeoutCircuitThreshold,
      timeoutCircuitCooldown: timeoutCircuitCooldown ?? this.timeoutCircuitCooldown,
      lateCallbackDrainWindow: lateCallbackDrainWindow ?? this.lateCallbackDrainWindow,
      backgroundRetry: backgroundRetry ?? this.backgroundRetry,
    );
  }
}
