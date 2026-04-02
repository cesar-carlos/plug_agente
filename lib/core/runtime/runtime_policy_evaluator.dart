import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';

/// Avalia política de capacidades baseado na versão do Windows.
class RuntimePolicyEvaluator {
  const RuntimePolicyEvaluator();

  RuntimeCapabilities evaluate(WindowsVersionInfo versionInfo) {
    if (versionInfo.isBelowWindows8) {
      return RuntimeCapabilities.unsupported(
        reasons: [
          'Sistema operacional abaixo do mínimo suportado',
          'Versão: ${versionInfo.versionString}',
          'Mínimo requerido: Windows 8 / Server 2012',
        ],
      );
    }

    if (versionInfo.isWindows8OrServer2012 || versionInfo.isWindows81OrServer2012R2) {
      final serverMessage = versionInfo.isServer
          ? 'Windows Server 2012/2012 R2: recursos de desktop desabilitados'
          : 'Windows 8/8.1: recursos de desktop podem estar limitados';

      return RuntimeCapabilities.degraded(
        reasons: [
          'Versão do Windows com suporte limitado',
          'Versão: ${versionInfo.versionString}',
          serverMessage,
        ],
      );
    }

    if (versionInfo.isWindows10OrLater && versionInfo.isServer) {
      return RuntimeCapabilities.degraded(
        reasons: [
          'Windows Server detectado',
          'Versão: ${versionInfo.versionString}',
          'Recursos de desktop desabilitados por política de servidor',
        ],
      );
    }

    return RuntimeCapabilities.full();
  }
}
