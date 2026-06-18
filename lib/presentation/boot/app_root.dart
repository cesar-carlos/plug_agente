import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/boot/app_root_providers.dart';
import 'package:plug_agente/presentation/boot/startup_auto_session_initializer.dart';
import 'package:provider/provider.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({
    required this.capabilities,
    this.initialRoute,
    this.runDeferredBootstrap,
    super.key,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrap;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildAppRootProviders(),
      child: _ProviderInitializer(
        initialRoute: initialRoute,
        capabilities: capabilities,
        runDeferredBootstrap: runDeferredBootstrap,
      ),
    );
  }
}

class _ProviderInitializer extends StatefulWidget {
  const _ProviderInitializer({
    required this.capabilities,
    this.initialRoute,
    this.runDeferredBootstrap,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrap;

  @override
  State<_ProviderInitializer> createState() => _ProviderInitializerState();
}

class _ProviderInitializerState extends State<_ProviderInitializer> {
  var _isReassembling = false;

  @override
  void reassemble() {
    _isReassembling = true;
    super.reassemble();
  }

  @override
  void dispose() {
    final shouldMarkDrainingOnDispose =
        !_isReassembling &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.detached;
    if (shouldMarkDrainingOnDispose && getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      final guard = getIt<AgentActionRuntimeStateGuard>();
      if (guard.snapshot.status != AgentActionSubsystemStatus.draining) {
        guard.markDraining(
          reason: AgentActionRuntimeStateConstants.appRootDisposeReason,
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StartupAutoSessionInitializer(
      hubSessionCoordinator: getIt<HubSessionCoordinator>(),
      runDeferredBootstrapBeforeConnect: widget.runDeferredBootstrap,
      child: PlugAgentApp(
        initialRoute: widget.initialRoute,
        capabilities: widget.capabilities,
      ),
    );
  }
}
