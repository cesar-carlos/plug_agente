import 'package:plug_agente/core/runtime/runtime_capabilities.dart';

class AppBootstrapData {
  const AppBootstrapData({
    required this.capabilities,
    required this.initialRoute,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
}
