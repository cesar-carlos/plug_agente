import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:plug_agente/infrastructure/actions/com_object_production_registrations.dart';
import 'package:plug_agente/infrastructure/actions/com_object_stub_invocation_handler.dart';

/// Builds the COM invocation registry for dependency injection.
abstract final class ComObjectInvocationBootstrap {
  static const String stubEnabledKey = 'AGENT_ACTION_COM_STUB_ENABLED';
  static const String stubProgIdKey = 'AGENT_ACTION_COM_STUB_PROG_ID';
  static const String stubMemberNameKey = 'AGENT_ACTION_COM_STUB_MEMBER_NAME';

  static const String defaultStubProgId = 'AgentAction.Test';
  static const String defaultStubMemberName = 'Ping';

  static ComObjectInvocationRegistry createRegistry() {
    return ComObjectInvocationRegistry(buildRegistrations());
  }

  static List<RegisteredComObjectInvocation> buildRegistrations() {
    return <RegisteredComObjectInvocation>[
      ...buildComObjectProductionRegistrations(),
      ...buildStubRegistrationsFromEnvironment(),
    ];
  }

  static List<RegisteredComObjectInvocation> buildStubRegistrationsFromEnvironment() {
    final enabled = AppEnvironment.get(stubEnabledKey)?.trim().toLowerCase();
    if (enabled != 'true' && enabled != '1') {
      return const <RegisteredComObjectInvocation>[];
    }

    final progId = AppEnvironment.get(stubProgIdKey)?.trim();
    final memberName = AppEnvironment.get(stubMemberNameKey)?.trim();
    if (progId == null || progId.isEmpty || memberName == null || memberName.isEmpty) {
      return const <RegisteredComObjectInvocation>[];
    }

    if (progId.length > AgentActionComObjectConstants.maxProgIdLength ||
        memberName.length > AgentActionComObjectConstants.maxMemberNameLength) {
      return const <RegisteredComObjectInvocation>[];
    }

    return <RegisteredComObjectInvocation>[
      RegisteredComObjectInvocation(
        progId: progId,
        memberName: memberName,
        handler: const ComObjectStubInvocationHandler(),
      ),
    ];
  }
}
