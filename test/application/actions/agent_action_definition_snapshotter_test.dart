import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_remote_approval_reconciler.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

void main() {
  const snapshotter = AgentActionDefinitionSnapshotter();
  const reconciler = AgentActionRemoteApprovalReconciler(snapshotter);

  group('AgentActionDefinitionSnapshotter.riskFingerprint', () {
    test('should change fingerprint when command changes', () {
      const base = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final changed = base.copyWith(
        config: const CommandLineActionConfig(command: 'dir /b'),
      );

      expect(
        snapshotter.riskFingerprint(base),
        isNot(equals(snapshotter.riskFingerprint(changed))),
      );
    });

    test('should change fingerprint when stdout encoding policy changes', () {
      const base = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final changed = base.copyWith(
        policies: const AgentActionDefinitionPolicies(
          encoding: AgentActionEncodingPolicy(stdout: AgentActionOutputEncodingMode.utf8),
        ),
      );

      expect(
        snapshotter.riskFingerprint(base),
        isNot(equals(snapshotter.riskFingerprint(changed))),
      );
    });

    test('should change fingerprint when referenced secret content changes', () {
      const base = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );

      expect(
        snapshotter.riskFingerprint(
          base,
          secretReferenceFingerprints: const <String, String>{'api': 'sha256:one'},
        ),
        isNot(
          equals(
            snapshotter.riskFingerprint(
              base,
              secretReferenceFingerprints: const <String, String>{'api': 'sha256:two'},
            ),
          ),
        ),
      );
    });

    test('should change fingerprint when remote ad-hoc policy changes', () {
      const base = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(isEnabled: true),
        ),
      );
      final changed = base.copyWith(
        policies: const AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
          ),
        ),
      );

      expect(
        snapshotter.riskFingerprint(base),
        isNot(equals(snapshotter.riskFingerprint(changed))),
      );
    });
  });

  group('AgentActionRemoteApprovalReconciler', () {
    test('should require reapproval when risk fingerprint changes after approval', () {
      final approvedAt = DateTime.utc(2026, 5, 19, 10);
      final definition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir /b'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
      );

      const previousDefinition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(isEnabled: true),
        ),
      );

      final previous = AgentActionRemotePolicy(
        isEnabled: true,
        approvedAt: approvedAt,
        approvedBy: 'local-ui',
        riskFingerprint: snapshotter.riskFingerprint(previousDefinition),
      );

      final reconciled = reconciler.reconcile(
        incoming: definition.policies.remote,
        previous: previous,
        definition: definition,
      );

      expect(reconciled.requiresReapproval, isTrue);
      expect(reconciled.canRunSavedAction, isFalse);
    });

    test('should stamp fingerprint on fresh remote approval', () {
      final approvedAt = DateTime.utc(2026, 5, 19, 12);
      final definition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
      );

      final reconciled = reconciler.reconcile(
        incoming: definition.policies.remote,
        previous: null,
        definition: definition,
      );

      expect(reconciled.requiresReapproval, isFalse);
      expect(reconciled.riskFingerprint, snapshotter.riskFingerprint(definition));
      expect(reconciled.canRunSavedAction, isTrue);
    });

    test('should require reapproval on reconcileAsync when secret reference fingerprint changes', () async {
      final store = _SnapshotterTestSecretStore();
      await store.saveSecret('api', 'v1');
      final fingerprinter = AgentActionSecretReferenceFingerprinter(store);
      final asyncReconciler = AgentActionRemoteApprovalReconciler(
        snapshotter,
        secretFingerprinter: fingerprinter,
      );
      final approvedAt = DateTime.utc(2026, 5, 20, 10);
      const base = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );
      final initialFingerprints = await fingerprinter.fingerprintsFor(base);
      final previous = AgentActionRemotePolicy(
        isEnabled: true,
        approvedAt: approvedAt,
        approvedBy: 'local-ui',
        riskFingerprint: snapshotter.riskFingerprint(
          base,
          secretReferenceFingerprints: initialFingerprints,
        ),
      );

      await store.saveSecret('api', 'v2');
      final reconciled = await asyncReconciler.reconcileAsync(
        incoming: AgentActionRemotePolicy(
          isEnabled: true,
          approvedAt: approvedAt,
          approvedBy: 'local-ui',
        ),
        previous: previous,
        definition: base,
      );

      expect(reconciled.requiresReapproval, isTrue);
      expect(reconciled.canRunSavedAction, isFalse);
    });

    test('should accept reapproval when approvedAt is newer than previous approval', () {
      final previousApprovedAt = DateTime.utc(2026, 5, 19, 10);
      final reapprovedAt = DateTime.utc(2026, 5, 19, 14);
      const previousDefinition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(isEnabled: true),
        ),
      );
      final definition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir /b'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: reapprovedAt,
            approvedBy: 'local-ui',
          ),
        ),
      );

      final reconciled = reconciler.reconcile(
        incoming: definition.policies.remote,
        previous: AgentActionRemotePolicy(
          isEnabled: true,
          approvedAt: previousApprovedAt,
          approvedBy: 'local-ui',
          riskFingerprint: snapshotter.riskFingerprint(previousDefinition),
        ),
        definition: definition,
      );

      expect(reconciled.requiresReapproval, isFalse);
      expect(reconciled.riskFingerprint, snapshotter.riskFingerprint(definition));
      expect(reconciled.canRunSavedAction, isTrue);
    });
  });
}

class _SnapshotterTestSecretStore implements IAgentActionSecretStore {
  final Map<String, String> _secrets = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    _secrets.remove(secretName);
  }

  @override
  Future<bool> exists(String secretName) async => _secrets.containsKey(secretName);

  @override
  Future<String?> readSecret(String secretName) async => _secrets[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _secrets[secretName] = secretValue;
  }
}
