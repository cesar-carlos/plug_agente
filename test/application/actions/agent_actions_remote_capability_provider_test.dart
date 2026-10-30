import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';

void main() {
  Map<String, dynamic> build(AgentActionsRemoteCapabilityProvider provider) => provider.buildForTransport(
    supportedTypes: ['executable'],
    maintenanceModeEnabled: false,
    maintenanceStrictModeEnabled: false,
    remoteAdHocEnabled: false,
    elevatedActionsEnabled: false,
  );

  test('ready faithful runtime advertises I/O and removes it when readiness is lost', () {
    var available = true;
    final provider = AgentActionsRemoteCapabilityProvider(
      runtimeStateGuard: AgentActionRuntimeStateGuard(),
      elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
      faithfulIoAvailable: () => available,
    );
    final ready = build(provider);
    expect(ready['io'], ActionIoCapability.advertisement);
    expect(ready['methods'], contains('agent.action.sendInput'));
    expect(ready['supportedMethods'], contains('agent.action.readIo'));
    expect(ready['authorizationScopes'], contains('agent_actions.io'));
    available = false;
    final unavailable = build(provider);
    expect(unavailable.containsKey('io'), isFalse);
    expect(unavailable['methods'], isNot(contains('agent.action.sendInput')));
    expect(unavailable['authorizationScopes'], isNot(contains('agent_actions.io')));
  });

  test('legacy provider does not advertise faithful I/O by default', () {
    final provider = AgentActionsRemoteCapabilityProvider(
      runtimeStateGuard: AgentActionRuntimeStateGuard(),
      elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
    );
    expect(build(provider).containsKey('io'), isFalse);
  });

  test('transport registration includes I/O only with opt-in and ready storage', () async {
    final flags = FeatureFlags(
      InMemoryAppSettingsStore({
        'feature_enable_agent_actions': true,
        'feature_enable_remote_agent_actions': true,
      }),
    );
    var ready = false;
    var accepting = true;
    final provider = AgentActionsRemoteCapabilityProvider(
      runtimeStateGuard: AgentActionRuntimeStateGuard(),
      elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
      faithfulIoAvailable: () => flags.enableActionIo && ready && accepting,
    );
    final builder = TransportLocalCapabilitiesBuilder(
      featureFlags: flags,
      agentActionsRemoteCapabilityProvider: provider,
    );
    bool advertised() {
      builder.invalidateCache();
      return ActionIoCapability.negotiated(builder.build().extensions);
    }

    expect(advertised(), isFalse);
    await flags.setEnableActionIo(true);
    expect(advertised(), isFalse);
    ready = true;
    expect(advertised(), isTrue);
    accepting = false;
    expect(advertised(), isFalse);
    accepting = true;
    await flags.setEnableRemoteAgentActions(false);
    expect(advertised(), isFalse);
  });
}
