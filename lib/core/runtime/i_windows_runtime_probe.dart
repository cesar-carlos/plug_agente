import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:result_dart/result_dart.dart';

abstract class IWindowsRuntimeProbe {
  RuntimeDetectionDiagnostics? get lastDiagnostics;

  Future<Result<WindowsVersionInfo>> detect();
}
