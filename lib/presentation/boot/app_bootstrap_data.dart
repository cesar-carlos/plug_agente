import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';

class AppBootstrapData {
  const AppBootstrapData({
    required this.capabilities,
    required this.initialRoute,
    this.runDeferredBootstrap,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrap;
}
