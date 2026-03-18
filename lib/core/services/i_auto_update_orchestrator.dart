import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAutoUpdateOrchestrator {
  bool get isAvailable;
  UpdateCheckDiagnostics? get lastManualDiagnostics;

  Future<void> initialize();

  Future<void> checkInBackground();

  Future<Result<bool>> checkManual();
}
