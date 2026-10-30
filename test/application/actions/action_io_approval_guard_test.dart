import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_approval_guard.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  const guard = ActionIoApprovalGuard();
  const snapshotter = AgentActionDefinitionSnapshotter();
  final definition = AgentActionDefinition(
    id: 'saved',
    name: 'Saved',
    state: AgentActionState.active,
    config: const CommandLineActionConfig(command: 'echo saved'),
    policies: AgentActionDefinitionPolicies(
      remote: AgentActionRemotePolicy(
        isEnabled: true,
        allowFaithfulIo: true,
        approvedAt: DateTime.utc(2026),
      ),
    ),
  );
  final approved = definition.copyWith(
    policies: definition.policies.copyWith(
      remote: definition.policies.remote.copyWith(riskFingerprint: snapshotter.riskFingerprint(definition)),
    ),
  );

  test('accepts only an approval matching the current definition and mode', () async {
    final result = await guard.validate(
      definition: approved,
      snapshotter: snapshotter,
      secretFingerprints: () async => {},
    );
    expect(result.isSuccess(), isTrue);
    for (final candidate in [
      definition,
      approved.copyWith(config: const CommandLineActionConfig(command: 'echo changed')),
      approved.copyWith(
        policies: approved.policies.copyWith(remote: approved.policies.remote.copyWith(allowFaithfulIo: false)),
      ),
      approved.copyWith(
        policies: approved.policies.copyWith(remote: approved.policies.remote.copyWith(requiresReapproval: true)),
      ),
    ]) {
      final rejected = await guard.validate(
        definition: candidate,
        snapshotter: snapshotter,
        secretFingerprints: () async => {},
      );
      expect(rejected.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((rejected.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_NOT_APPROVED');
    }
  });

  test('missing verification dependencies and failed secret reads never bypass approval', () async {
    final missing = await guard.validate(definition: approved, snapshotter: null, secretFingerprints: null);
    expect(missing.isError(), isTrue);
    final unavailable = await guard.validate(
      definition: approved,
      snapshotter: snapshotter,
      secretFingerprints: () async => throw Exception('private storage diagnostic'),
    );
    final failure = unavailable.exceptionOrNull()! as ActionAuthorizationFailure;
    expect(failure.code, 'ACTION_IO_APPROVAL_UNAVAILABLE');
    expect(failure.message, isNot(contains('private storage')));
    expect(failure.cause, isA<Exception>());
  });
}
