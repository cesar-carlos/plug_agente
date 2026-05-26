import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAutoUpdateOrchestrator {
  bool get isAvailable;
  bool get automaticSilentUpdatesEnabled;

  /// `true` while a silent update download/install cycle is in progress.
  /// Useful for the UI to show a progress indicator without polling.
  bool get isSilentCheckInProgress;
  UpdateCheckDiagnostics? get lastManualDiagnostics;
  UpdateCheckDiagnostics? get lastBackgroundDiagnostics;
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics;

  Future<void> initialize();

  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled);

  Future<void> startAutomaticChecks();

  Future<void> checkInBackground();

  /// Triggers a silent update cycle. The success bucket carries the
  /// [SilentUpdateOutcome] discriminator so callers can distinguish
  /// "installer launched" from "no new version", "rollout skipped",
  /// "cooldown active", "cancelled", etc.
  Future<Result<SilentUpdateOutcome>> checkSilently();

  /// Triggers a WinSparkle-driven manual check. The success bucket reports
  /// `true` when WinSparkle found an update and `false` when the remote
  /// reports up-to-date.
  Future<Result<bool>> checkManual();
}
