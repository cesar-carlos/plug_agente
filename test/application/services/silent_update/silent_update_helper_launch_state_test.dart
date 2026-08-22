import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_helper_launch_state.dart';

SilentUpdateLauncherStatus _status({
  required String state,
  bool? elevatedCancelled,
  DateTime? lastUpdatedAt,
}) {
  return SilentUpdateLauncherStatus(
    state: state,
    strategy: 'currentUserThenElevated',
    installDirectory: r'C:\App',
    installerPath: r'C:\App\updates\setup.exe',
    logPath: r'C:\App\updates\update.log',
    nonAdminExitCode: null,
    nonAdminDurationMs: null,
    elevatedExitCode: null,
    elevatedDurationMs: null,
    elevatedRetryStarted: null,
    waitForAppExitDurationMs: null,
    appExitTimedOut: null,
    appPid: 1,
    signatureStatus: null,
    signatureRequired: null,
    actualSha256: null,
    hashValidationStatus: null,
    installDirectoryWritable: true,
    elevatedCancelled: elevatedCancelled,
    errorMessage: null,
    lastUpdatedAt: lastUpdatedAt ?? DateTime.utc(2026, 6, 10, 10),
  );
}

void main() {
  final now = DateTime.utc(2026, 6, 10, 12);
  const wait = Duration(minutes: 30);

  group('SilentUpdateHelperLaunchState', () {
    test('UAC cancel is not a concluded launch', () {
      final status = _status(state: 'elevatedCancelled', elevatedCancelled: true);

      expect(SilentUpdateHelperLaunchState.isUserCancelledElevation(status), isTrue);
      expect(
        SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
          launcherStatus: status,
          now: now,
          helperWaitDuration: wait,
        ),
        isFalse,
      );
      expect(SilentUpdateHelperLaunchState.isInFlight(
        launchedAt: DateTime.utc(2026, 6, 10, 10),
        launcherStatus: status,
        now: now,
        helperWaitDuration: wait,
      ), isFalse);
    });

    test('elevatedCancelled flag is enough even when state is missing', () {
      final status = _status(state: 'unknown', elevatedCancelled: true);

      expect(SilentUpdateHelperLaunchState.isUserCancelledElevation(status), isTrue);
      expect(
        SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
          launcherStatus: status,
          now: now,
          helperWaitDuration: wait,
        ),
        isFalse,
      );
    });

    test('elevatedFailed is a concluded terminal failure', () {
      final status = _status(state: 'elevatedFailed');

      expect(SilentUpdateHelperLaunchState.isTerminalFailure(status), isTrue);
      expect(
        SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
          launcherStatus: status,
          now: now,
          helperWaitDuration: wait,
        ),
        isTrue,
      );
    });

    test('launcherFailed and nonAdminFailed are terminal failures', () {
      expect(
        SilentUpdateHelperLaunchState.isTerminalFailure(_status(state: 'launcherFailed')),
        isTrue,
      );
      expect(
        SilentUpdateHelperLaunchState.isTerminalFailure(_status(state: 'nonAdminFailed')),
        isTrue,
      );
    });
  });
}
