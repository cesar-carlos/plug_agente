import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:result_dart/result_dart.dart';

/// Owns the periodic silent-check timer, quiet-hours gate, and automatic
/// failure cooldown pre-check for the silent update path.
class SilentUpdateScheduler {
  SilentUpdateScheduler({
    required PersistentCircuitBreaker automaticFailureBreaker,
    Duration Function()? bootJitterProvider,
    DateTime Function()? clock,
  }) : _automaticFailureBreaker = automaticFailureBreaker,
       _bootJitterProvider = bootJitterProvider,
       _clock = clock ?? DateTime.now;

  final PersistentCircuitBreaker _automaticFailureBreaker;
  final Duration Function()? _bootJitterProvider;
  final DateTime Function() _clock;

  Timer? _automaticCheckTimer;

  bool isWithinQuietHours() {
    final environmentSnapshot = AppEnvironment.snapshot();
    final quietHoursStart = resolveAutoUpdateQuietHoursStartMinute(environment: environmentSnapshot);
    final quietHoursEnd = resolveAutoUpdateQuietHoursEndMinute(environment: environmentSnapshot);
    final quietNow = _clock();
    final quietNowMinutes = quietNow.hour * 60 + quietNow.minute;
    return isWithinQuietHoursWindow(
      nowMinutes: quietNowMinutes,
      startMinute: quietHoursStart,
      endMinute: quietHoursEnd,
    );
  }

  Future<Result<SilentUpdateOutcome>?> buildCooldownResult({
    required String feedUrl,
    required String? checkId,
    required void Function(UpdateCheckDiagnostics diagnostics) onDiagnostics,
    required Future<void> Function() persistDiagnostics,
  }) async {
    final remaining = await _automaticFailureBreaker.remainingCooldown();
    if (remaining == null) return null;
    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = _clock();
    onDiagnostics(
      UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: checkId,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticCooldown,
        updateAvailable: false,
        automaticFailureCount: _automaticFailureBreaker.failureCount,
        automaticCooldownUntil: _automaticFailureBreaker.cooldownUntil,
        errorMessage:
            'Automatic silent updates are paused after repeated failures. Try again in about $humanRemaining.',
      ),
    );
    await persistDiagnostics();
    return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.cooldownActive);
  }

  void scheduleAndStart({
    required bool runImmediately,
    required Future<void> Function() onCheck,
  }) {
    stop();
    if (runImmediately) {
      final jitter = _bootJitterProvider?.call();
      if (jitter == null || jitter <= Duration.zero) {
        unawaited(onCheck());
      } else {
        Timer(jitter, () => unawaited(onCheck()));
      }
    }
    final intervalSeconds = resolveAutoUpdateCheckIntervalSeconds(
      environment: AppEnvironment.snapshot(),
    );
    if (intervalSeconds > 0) {
      _automaticCheckTimer = Timer.periodic(
        Duration(seconds: intervalSeconds),
        (_) => unawaited(onCheck()),
      );
      developer.log(
        'Silent update periodic timer scheduled (interval: ${intervalSeconds}s)',
        name: 'silent_update_scheduler',
        level: 800,
      );
    }
  }

  void stop() {
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;
  }
}
