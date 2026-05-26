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

  Future<Result<bool>> checkSilently();

  Future<Result<bool>> checkManual();
}
