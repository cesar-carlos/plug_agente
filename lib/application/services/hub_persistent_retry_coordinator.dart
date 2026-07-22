import 'dart:async';

import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/transport_reconnect_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Timer-driven persistent hub retry ticks and failure exhaustion policy.
final class HubPersistentRetryCoordinator {
  HubPersistentRetryCoordinator({
    required HubPersistentRetryRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubPersistentRetryRuntimeDependencies _deps;

  Timer? _timer;
  bool _inFlight = false;
  int _failureLogCount = 0;
  bool _sessionBudgetsCaptured = false;

  /// Budgets captured at [start] so Diagnostics Apply takes effect on the next
  /// persistent start (not mid-flight bumps).
  int _sessionMaxFailedTicks = 0;
  int _sessionMaxUnreachableFailedTicks = 0;

  bool get hasActiveTimer => _timer != null;

  bool get retryInFlight => _inFlight;

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Starts persistent retry using the effective interval/budgets at call time
  /// (Diagnostics Apply is picked up on the next [start], without app restart).
  void start({Duration? interval}) {
    cancelTimer();
    _deps.resetPersistentRetryCounters();
    _failureLogCount = 0;
    final effectiveInterval = interval ?? _deps.persistentRetryInterval();
    _sessionMaxFailedTicks = _deps.maxFailedTicks();
    _sessionMaxUnreachableFailedTicks = _deps.maxUnreachableFailedTicks();
    _sessionBudgetsCaptured = true;
    final ctx = _deps.resolveConnectionContext();
    AppLogger.debug(
      'resilience: ${_deps.resilienceLogPrefix()}persistent_retry event=started '
      'interval_ms=${effectiveInterval.inMilliseconds} '
      'max_failed_ticks=$_sessionMaxFailedTicks '
      'max_unreachable_failed_ticks=$_sessionMaxUnreachableFailedTicks '
      'agent_id=${ctx?.agentId ?? "?"}',
    );
    unawaited(tick());
    _timer = Timer.periodic(effectiveInterval, (_) {
      unawaited(tick());
    });
  }

  Future<void> tick() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    try {
      await _deps.runPersistentTick();
    } finally {
      _inFlight = false;
    }
  }

  void bumpPersistentReconnectFailure(
    HubConnectionContext context, {
    required String reason,
    required HubRecoveryOrchestrator orchestrator,
  }) {
    final isUnreachable = reason == TransportReconnectConstants.hubUnreachableReason;
    if (isUnreachable) {
      orchestrator.bumpPersistentUnreachableFailure();
    } else {
      orchestrator.bumpPersistentFailure();
    }

    final relevantMax = isUnreachable
        ? (_sessionBudgetsCaptured ? _sessionMaxUnreachableFailedTicks : _deps.maxUnreachableFailedTicks())
        : (_sessionBudgetsCaptured ? _sessionMaxFailedTicks : _deps.maxFailedTicks());
    if (relevantMax <= 0) {
      return;
    }

    final failureCount = isUnreachable
        ? orchestrator.persistentUnreachableFailureCount
        : orchestrator.persistentFailureCount;

    _failureLogCount++;
    const stride = ConnectionConstants.hubReconnectFailureLogThrottleStride;
    if (_failureLogCount == 1 || _failureLogCount % stride == 0) {
      AppLogger.debug(
        'resilience: ${_deps.resilienceLogPrefix()}hub_persistent_retry_failure '
        'count=$failureCount '
        'logged_failures=$_failureLogCount '
        'stride=$stride '
        'max=$relevantMax '
        'budget=${isUnreachable ? "unreachable" : "socket"} '
        'reason=$reason '
        'agent_id=${context.agentId}',
      );
    }
    if (failureCount >= relevantMax) {
      cancelTimer();
      _deps.onPersistentRetryExhausted(context, failureCount);
    }
  }

  void dispose() {
    cancelTimer();
  }
}

final class HubPersistentRetryRuntimeDependencies {
  HubPersistentRetryRuntimeDependencies({
    required this.resilienceLogPrefix,
    required this.maxFailedTicks,
    required this.maxUnreachableFailedTicks,
    required this.persistentRetryInterval,
    required this.resolveConnectionContext,
    required this.runPersistentTick,
    required this.resetPersistentRetryCounters,
    required this.onPersistentRetryExhausted,
  });

  final String Function() resilienceLogPrefix;

  /// Socket-reconnect failure budget (`0` = unlimited). Snapshotted on [HubPersistentRetryCoordinator.start].
  final int Function() maxFailedTicks;

  /// Hub-unreachable failure budget (`0` = unlimited). Snapshotted on [HubPersistentRetryCoordinator.start].
  final int Function() maxUnreachableFailedTicks;

  /// Effective persistent retry interval. Re-read on each [HubPersistentRetryCoordinator.start].
  final Duration Function() persistentRetryInterval;

  final HubConnectionContext? Function() resolveConnectionContext;
  final Future<void> Function() runPersistentTick;
  final void Function() resetPersistentRetryCounters;
  final void Function(HubConnectionContext context, int failureCount) onPersistentRetryExhausted;
}
