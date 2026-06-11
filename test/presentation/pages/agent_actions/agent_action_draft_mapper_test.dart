import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_mapper.dart';

void main() {
  group('AgentActionDraftMapper.clear', () {
    test('resets every controller and flag to the defaults a fresh editor expects', () {
      final draft = AgentActionDraft()
        ..identity.name.text = 'leftover'
        ..commandLine.command.text = 'old command'
        ..executable.targetPath.text = r'C:\old.exe'
        ..email.from.text = 'old@example.com'
        ..developer.executorPath.text = r'C:\Data7\bin\Executor.exe'
        ..maxAttempts = 5
        ..notifyOnSuccess = true
        ..remoteEnabled = true
        ..runElevated = true
        ..editingActionId = 'previous-action'
        ..isDraftModifiedSinceLoad = true;

      var clearedConnections = 0;
      var dirtyValue = true;
      var lastSetKind = AgentActionDraftKind.executable;

      const mapper = AgentActionDraftMapper();
      mapper.clear(
        draft,
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () => clearedConnections++,
          markDirty: (value) => dirtyValue = value,
          setDraftKind: (kind) => lastSetKind = kind,
        ),
      );

      expect(draft.editingActionId, isNull);
      expect(draft.identity.name.text, isEmpty);
      expect(draft.commandLine.command.text, isEmpty);
      expect(draft.executable.targetPath.text, isEmpty);
      expect(draft.email.from.text, isEmpty);
      expect(draft.developer.executorPath.text, isEmpty);
      expect(draft.comObject.arguments.text, '{}', reason: 'COM arguments fall back to the empty JSON object');
      expect(draft.executionPolicy.acceptedExitCodes.text, '0');
      expect(draft.executionPolicy.maxConcurrent.text, '1');
      expect(draft.executionPolicy.maxQueued.text, '100');
      expect(draft.executionPolicy.maxRuntimeMinutes.text, '30');
      expect(draft.maxAttempts, 1);
      expect(draft.maxRuntimeMinutes, 30);
      expect(draft.notifyOnSuccess, isFalse);
      expect(draft.notifyOnFailure, isFalse);
      expect(draft.notifyOnTimeout, isFalse);
      expect(draft.remoteEnabled, isFalse);
      expect(draft.remoteAdHoc, isFalse);
      expect(draft.remoteApprovalGranted, isFalse);
      expect(draft.runElevated, isFalse);
      expect(draft.state, AgentActionState.needsValidation);
      expect(draft.isDraftModifiedSinceLoad, isFalse);
      expect(draft.validationMessage, isNull);

      expect(clearedConnections, 1, reason: 'clear must flush the developer connections cache once');
      expect(dirtyValue, isFalse, reason: 'clear must reset the dirty notifier');
      expect(
        lastSetKind,
        AgentActionDraftKind.commandLine,
        reason: 'preserves the current draft kind when none is given',
      );
    });

    test('uses the supplied draft kind when present', () {
      final draft = AgentActionDraft();
      AgentActionDraftKind? lastKind;

      const AgentActionDraftMapper().clear(
        draft,
        draftKind: AgentActionDraftKind.email,
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () {},
          markDirty: (_) {},
          setDraftKind: (kind) => lastKind = kind,
        ),
      );

      expect(lastKind, AgentActionDraftKind.email);
    });
  });

  group('AgentActionDraftMapper.applyDefinition', () {
    test('null definition delegates to clear', () {
      final draft = AgentActionDraft()
        ..identity.name.text = 'old'
        ..editingActionId = 'old-id';

      var cleared = 0;
      const AgentActionDraftMapper().applyDefinition(
        draft,
        null,
        capabilities: const AgentActionDraftCapabilities(remoteAdHocEnabled: false, elevatedEnabled: false),
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () => cleared++,
          markDirty: (_) {},
          setDraftKind: (_) {},
        ),
      );

      expect(draft.editingActionId, isNull);
      expect(draft.identity.name.text, isEmpty);
      expect(cleared, 1);
    });

    test('command-line definition maps identity, policies, command and clears other kinds', () {
      final draft = AgentActionDraft()
        ..email.from.text = 'old@example.com'
        ..jar.path.text = r'C:\old.jar';

      const definition = AgentActionDefinition(
        id: 'cmd-1',
        name: 'Run dir',
        description: 'Lists files',
        config: CommandLineActionConfig(command: 'dir'),
        state: AgentActionState.active,
      );

      var lastKind = AgentActionDraftKind.email;
      const AgentActionDraftMapper().applyDefinition(
        draft,
        definition,
        capabilities: const AgentActionDraftCapabilities(remoteAdHocEnabled: true, elevatedEnabled: true),
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () {},
          markDirty: (_) {},
          setDraftKind: (kind) => lastKind = kind,
        ),
      );

      expect(draft.editingActionId, 'cmd-1');
      expect(draft.identity.name.text, 'Run dir');
      expect(draft.identity.description.text, 'Lists files');
      expect(draft.commandLine.command.text, 'dir');
      expect(draft.state, AgentActionState.active);
      expect(lastKind, AgentActionDraftKind.commandLine);
      expect(draft.email.from.text, isEmpty, reason: 'other kinds are cleared');
      expect(draft.jar.path.text, isEmpty);
      expect(draft.applyingLoadedDefinition, isFalse, reason: 'flag is cleared in finally even on success');
    });

    test('email definition maps every email controller', () {
      final draft = AgentActionDraft();

      const definition = AgentActionDefinition(
        id: 'email-1',
        name: 'Notify',
        config: EmailActionConfig(
          smtpProfileId: 'profile-a',
          from: 'agent@example.com',
          to: ['ops@example.com', 'dba@example.com'],
          cc: ['cc@example.com'],
          subjectTemplate: 'Alert',
          bodyTemplate: 'Hello',
        ),
      );

      const AgentActionDraftMapper().applyDefinition(
        draft,
        definition,
        capabilities: const AgentActionDraftCapabilities(remoteAdHocEnabled: false, elevatedEnabled: false),
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () {},
          markDirty: (_) {},
          setDraftKind: (_) {},
        ),
      );

      expect(draft.email.smtpProfileId.text, 'profile-a');
      expect(draft.email.from.text, 'agent@example.com');
      expect(draft.email.to.text, 'ops@example.com\ndba@example.com');
      expect(draft.email.cc.text, 'cc@example.com');
      expect(draft.email.bcc.text, isEmpty);
      expect(draft.email.subject.text, 'Alert');
      expect(draft.email.body.text, 'Hello');
      expect(draft.email.attachments.text, isEmpty);
    });

    test('developer definition schedules connection reload with saved connection id', () {
      final draft = AgentActionDraft();
      final definition = AgentActionDefinition(
        id: 'dev-1',
        name: 'Transmitir Data7',
        config: DeveloperActionConfig.data7Executor(
          executorPath: const AgentActionPathReference(originalPath: r'C:\Data7\bin\Executor.exe'),
          projectPath: const AgentActionPathReference(originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj'),
          data7ConfigPath: const AgentActionPathReference(originalPath: r'C:\Data7\bin\Data7.Config'),
          connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
          connectionLabel: 'Estacao',
        ),
      );

      String? scheduledConnectionId;
      AgentActionPathPolicy? scheduledPathPolicy;

      const AgentActionDraftMapper().applyDefinition(
        draft,
        definition,
        capabilities: const AgentActionDraftCapabilities(remoteAdHocEnabled: false, elevatedEnabled: false),
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () {},
          markDirty: (_) {},
          setDraftKind: (_) {},
          scheduleDeveloperConnectionReload: ({required pathPolicy, required selectedConnectionId}) {
            scheduledPathPolicy = pathPolicy;
            scheduledConnectionId = selectedConnectionId;
          },
        ),
      );

      expect(draft.developer.data7ConfigPath.text, r'C:\Data7\bin\Data7.Config');
      expect(draft.developer.connectionId.text, '34512A51-672C-4ECE-9991-F43E175E7A8B');
      expect(scheduledConnectionId, '34512A51-672C-4ECE-9991-F43E175E7A8B');
      expect(scheduledPathPolicy, definition.policies.path);
    });

    test('capabilities flags gate remote ad-hoc and elevated', () {
      final draft = AgentActionDraft();
      const definition = AgentActionDefinition(
        id: 'cmd-2',
        name: 'Run',
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(isEnabled: true, allowAdHoc: true),
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );

      const AgentActionDraftMapper().applyDefinition(
        draft,
        definition,
        capabilities: const AgentActionDraftCapabilities(remoteAdHocEnabled: false, elevatedEnabled: false),
        hooks: AgentActionDraftMapperHooks(
          clearDeveloperConnections: () {},
          markDirty: (_) {},
          setDraftKind: (_) {},
        ),
      );

      expect(draft.remoteEnabled, isTrue, reason: 'remoteEnabled is independent of the ad-hoc capability');
      expect(draft.remoteAdHoc, isFalse, reason: 'ad-hoc is muted when the runtime disabled it');
      expect(draft.runElevated, isFalse, reason: 'elevated is muted when the runtime disabled it');
    });
  });
}
