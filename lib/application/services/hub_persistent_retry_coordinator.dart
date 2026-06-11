import 'dart:async';

import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
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

  bool get hasActiveTimer => _timer != null;

  bool get retryInFlight => _inFlight;

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void start({required Duration interval}) {
    cancelTimer();
    _deps.resetPersistentRetryCounters();
    _failureLogCount = 0;
    final ctx = _deps.resolveConnectionContext();
    AppLogger.debug(
      'resilience: ${_deps.resilienceLogPrefix()}persistent_retry event=started '
      'interval_ms=${interval.inMilliseconds} '
      'max_failed_ticks=${_deps.maxFailedTicks} '
      'agent_id=${ctx?.agentId ?? "?"}',
    );
    unawaited(tick());
    _timer = Timer.periodic(interval, (_) {
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
    if (_deps.maxFailedTicks <= 0) {
      return;
    }
    orchestrator.bumpPersistentFailure();
    _failureLogCount++;
    const stride = ConnectionConstants.hubReconnectFailureLogThrottleStride;
    if (_failureLogCount == 1 || _failureLogCount % stride == 0) {
      AppLogger.debug(
        'resilience: ${_deps.resilienceLogPrefix()}hub_persistent_retry_failure '
        'count=${orchestrator.persistentFailureCount} '
        'logged_failures=$_failureLogCount '
        'stride=$stride '
        'max=${_deps.maxFailedTicks} '
        'reason=$reason '
        'agent_id=${context.agentId}',
      );
    }
    if (orchestrator.persistentFailureCount >= _deps.maxFailedTicks) {
      cancelTimer();
      _deps.onPersistentRetryExhausted(context, orchestrator.persistentFailureCount);
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
    required this.resolveConnectionContext,
    required this.runPersistentTick,
    required this.resetPersistentRetryCounters,
    required this.onPersistentRetryExhausted,
  });

  final String Function() resilienceLogPrefix;
  final int maxFailedTicks;
  final HubConnectionContext? Function() resolveConnectionContext;
  final Future<void> Function() runPersistentTick;
  final void Function() resetPersistentRetryCounters;
  final void Function(HubConnectionContext context, int failureCount) onPersistentRetryExhausted;
}
