import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:result_dart/result_dart.dart';

class FakeSilentUpdateCoordinator implements ISilentUpdateCoordinator {
  bool _isSilentCheckInProgress = false;
  bool automaticSilentUpdatesEnabledValue = true;
  bool hasPendingDownloadedUpdateValue = false;
  UpdateCheckDiagnostics? lastAutomaticDiagnosticsValue;

  int reconcilePendingAndScheduleCallCount = 0;
  int scheduleAndStartCallCount = 0;
  int stopCallCount = 0;
  int checkSilentlyCallCount = 0;
  int applyPendingCallCount = 0;
  bool? lastApplyTriggerAppClose;
  String? lastApplyNoticeTitle;
  String? lastApplyNoticeBody;
  int hydrateCallCount = 0;
  int clearPersistedAutomaticDiagnosticsCallCount = 0;
  int requestCancellationCallCount = 0;

  Result<SilentUpdateOutcome> checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion);
  Result<void> applyPendingResult = const Success(unit);

  bool? lastCheckSilentlyUserInitiated;
  bool? lastScheduleAndStartRunImmediately;

  void setInProgress(bool value) => _isSilentCheckInProgress = value;

  @override
  bool get isSilentCheckInProgress => _isSilentCheckInProgress;

  @override
  bool get automaticSilentUpdatesEnabled => automaticSilentUpdatesEnabledValue;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => hasPendingDownloadedUpdateValue;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => lastAutomaticDiagnosticsValue;

  @override
  void hydratePersistedDiagnostics() => hydrateCallCount++;

  @override
  Future<void> clearPersistedAutomaticDiagnostics() async {
    clearPersistedAutomaticDiagnosticsCallCount++;
    lastAutomaticDiagnosticsValue = null;
  }

  @override
  Future<void> reconcilePendingAndSchedule() async => reconcilePendingAndScheduleCallCount++;

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently({bool userInitiated = false}) async {
    checkSilentlyCallCount++;
    lastCheckSilentlyUserInitiated = userInitiated;
    return checkSilentlyResult;
  }

  @override
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    applyPendingCallCount++;
    lastApplyNoticeTitle = noticeTitle;
    lastApplyNoticeBody = noticeBody;
    lastApplyTriggerAppClose = triggerAppClose;
    return applyPendingResult;
  }

  @override
  void scheduleAndStart({bool runImmediately = true}) {
    scheduleAndStartCallCount++;
    lastScheduleAndStartRunImmediately = runImmediately;
  }

  @override
  void stop() => stopCallCount++;

  @override
  void requestCancellation() => requestCancellationCallCount++;
}
