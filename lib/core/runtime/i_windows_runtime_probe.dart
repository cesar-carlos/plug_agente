import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:result_dart/result_dart.dart';

/// Interface para detecção de versão do Windows.
abstract class IWindowsRuntimeProbe {
  Future<Result<WindowsVersionInfo>> detect();
}
