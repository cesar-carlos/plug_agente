import 'dart:math';

import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';

/// Composition entry point for `HubRecoveryOrchestrator` (not registered as a GetIt singleton).
HubRecoveryOrchestrator createHubRecoveryOrchestrator({
  required Duration initialReconnectDelay,
  required Duration maxReconnectDelay,
  required HubRecoveryRuntimeDependencies runtime,
  Random? random,
}) {
  return HubRecoveryOrchestrator(
    initialReconnectDelay: initialReconnectDelay,
    maxReconnectDelay: maxReconnectDelay,
    random: random,
    runtime: runtime,
  );
}
