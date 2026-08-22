import 'package:plug_agente/domain/entities/pending_silent_update.dart';

/// Shared rules for distinguishing a *staged* silent update (downloaded,
/// helper not launched) from an *in-flight* helper install.
///
/// Download [PendingSilentUpdate.startedAt] must never be treated as launch
/// evidence on its own: that stamp is set when staging finishes, and using it
/// with a missing status file incorrectly blocks apply for the helper wait
/// window.
abstract final class SilentUpdateHelperLaunchState {
  SilentUpdateHelperLaunchState._();

  static const Set<String> inProgressStates = <String>{
    'started',
    'starting',
    'validatingHash',
    'waitingForAppExit',
    'nonAdminStarted',
    'elevatedStarted',
    'runningCurrentUser',
    'runningElevated',
  };

  static const Set<String> terminalFailureStates = <String>{
    'failed',
    'cancelled',
    'elevatedFailed',
    'launcherFailed',
    'nonAdminFailed',
  };

  /// Helper reached the UAC prompt and the operator cancelled it. The
  /// staged installer is still on disk and must stay Ready for an explicit
  /// retry — this is not an automatic-failure / cooldown event.
  static const Set<String> userCancelledElevationStates = <String>{
    'elevatedCancelled',
  };

  static const Set<String> terminalSuccessStates = <String>{
    'completed',
  };

  /// True when the helper was launched (persisted [launchedAt] and/or a
  /// status snapshot written by the helper), not merely staged on disk.
  static bool hasLaunchEvidence({
    required DateTime? launchedAt,
    required SilentUpdateLauncherStatus? launcherStatus,
  }) {
    return launchedAt != null || launcherStatus != null;
  }

  /// True while a launched helper is still within the wait window and has not
  /// reached a terminal status. Staged-only records always return false.
  static bool isInFlight({
    required DateTime? launchedAt,
    required SilentUpdateLauncherStatus? launcherStatus,
    required DateTime now,
    required Duration helperWaitDuration,
  }) {
    if (!hasLaunchEvidence(launchedAt: launchedAt, launcherStatus: launcherStatus)) {
      return false;
    }

    final state = launcherStatus?.state;
    if (launcherStatus != null && state != null && !inProgressStates.contains(state)) {
      return false;
    }

    final activityAt = launcherStatus?.lastUpdatedAt ?? launchedAt;
    if (activityAt == null) {
      return false;
    }

    return now.difference(activityAt) <= helperWaitDuration;
  }

  /// True when the helper reported that the operator cancelled the UAC
  /// elevation prompt. Artifacts stay valid for a later apply.
  static bool isUserCancelledElevation(SilentUpdateLauncherStatus? launcherStatus) {
    if (launcherStatus == null) return false;
    if (launcherStatus.elevatedCancelled ?? false) return true;
    final state = launcherStatus.state;
    return state != null && userCancelledElevationStates.contains(state);
  }

  /// Launch evidence exists but the helper is no longer in-flight (wait window
  /// elapsed or terminal status). Reconcile and resolve share this gate so both
  /// refuse Ready/retry and clear the pending record (fail + cooldown policy)
  /// instead of one path clearing and the other offering Install again.
  ///
  /// UAC cancellation is excluded: the operator can retry the same staged
  /// installer without waiting out the automatic failure cooldown.
  static bool isLaunchConcludedOrTimedOut({
    required DateTime? launchedAt,
    required SilentUpdateLauncherStatus? launcherStatus,
    required DateTime now,
    required Duration helperWaitDuration,
  }) {
    if (isUserCancelledElevation(launcherStatus)) return false;
    return hasLaunchEvidence(launchedAt: launchedAt, launcherStatus: launcherStatus) &&
        !isInFlight(
          launchedAt: launchedAt,
          launcherStatus: launcherStatus,
          now: now,
          helperWaitDuration: helperWaitDuration,
        );
  }

  static bool isTerminalSuccess(SilentUpdateLauncherStatus? launcherStatus) {
    final state = launcherStatus?.state;
    return state != null && terminalSuccessStates.contains(state);
  }

  static bool isTerminalFailure(SilentUpdateLauncherStatus? launcherStatus) {
    final state = launcherStatus?.state;
    return state != null && terminalFailureStates.contains(state);
  }

  /// Shared by reconcile and resolve so terminal-success accounting never
  /// diverges: reset the automatic failure breaker when the app version
  /// already caught up **or** the helper reported terminal success.
  static bool shouldResetBreakerForConcludedLaunch({
    required bool versionCompleted,
    required SilentUpdateLauncherStatus? launcherStatus,
  }) {
    return versionCompleted || isTerminalSuccess(launcherStatus);
  }

  /// Staged pending older than [stagedPendingTtl] measured from [startedAt].
  /// Null [startedAt] (legacy records) is treated as already expired so we do
  /// not keep untimestamped Ready forever.
  static bool isStagedPendingExpired({
    required DateTime? startedAt,
    required DateTime now,
    required Duration stagedPendingTtl,
  }) {
    if (startedAt == null) return true;
    return now.difference(startedAt) > stagedPendingTtl;
  }
}
