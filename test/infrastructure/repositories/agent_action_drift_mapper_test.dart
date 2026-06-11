import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_drift_mapper.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

void main() {
  const mapper = AgentActionDriftMapper();
  final now = DateTime.utc(2026, 6, 11, 12);

  group('AgentActionDriftMapper', () {
    test('round-trips command-line definition through drift data', () {
      final original = AgentActionDefinition(
        id: 'action-cmd',
        name: 'Command action',
        description: 'Runs a shell command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(
          command: 'echo hello',
          workingDirectory: AgentActionPathReference(originalPath: r'C:\work'),
        ),
        policies: const AgentActionDefinitionPolicies(
          encoding: AgentActionEncodingPolicy(
            stdout: AgentActionOutputEncodingMode.utf8,
            stderr: AgentActionOutputEncodingMode.utf8,
          ),
          exitCode: AgentActionExitCodePolicy(acceptedExitCodes: {0, 1}),
        ),
        definitionVersion: 2,
        definitionSnapshotHash: 'snapshot-hash-12345678',
        lastPreflightSnapshotHash: 'preflight-hash',
        lastPreflightValidatedAt: DateTime.utc(2026, 6, 10),
        createdAt: DateTime.utc(2026, 6),
        updatedAt: DateTime.utc(2026, 6, 2),
      );

      final data = mapper.definitionToData(original, now: now);
      final roundTripped = mapper.definitionFromData(data);

      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.description, original.description);
      expect(roundTripped.state, original.state);
      expect(roundTripped.definitionVersion, original.definitionVersion);
      expect(roundTripped.definitionSnapshotHash, original.definitionSnapshotHash);
      expect(roundTripped.lastPreflightSnapshotHash, original.lastPreflightSnapshotHash);
      expect(roundTripped.lastPreflightValidatedAt, original.lastPreflightValidatedAt);
      expect(roundTripped.createdAt, original.createdAt);
      expect(roundTripped.updatedAt, original.updatedAt);
      expect(roundTripped.config, isA<CommandLineActionConfig>());
      final config = roundTripped.config as CommandLineActionConfig;
      expect(config.command, 'echo hello');
      expect(config.workingDirectory?.originalPath, r'C:\work');
      expect(roundTripped.policies.encoding.stdout, AgentActionOutputEncodingMode.utf8);
      expect(roundTripped.policies.exitCode.acceptedExitCodes, {0, 1});
    });

    test('loads successExitCodes alias when acceptedExitCodes is absent', () {
      final definition = mapper.definitionFromData(
        AgentActionDefinitionData(
          id: 'action-exit-alias',
          name: 'Exit alias',
          type: AgentActionType.commandLine.name,
          state: AgentActionState.active.name,
          configJson: '{"command":"dir"}',
          policiesJson: '{"exitCode":{"successExitCodes":[0,2]}}',
          definitionVersion: 1,
          definitionSnapshotHash: 'hash',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(definition.policies.exitCode.acceptedExitCodes, {0, 2});
    });

    test('round-trips trigger and execution rows', () {
      final trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.interval,
        name: 'Every hour',
        schedule: const AgentActionTriggerSchedule(
          interval: Duration(hours: 1),
          weekdays: {1, 3, 5},
          timezoneId: 'UTC',
        ),
        lastScheduledAt: DateTime.utc(2026, 6, 11, 10),
        createdAt: DateTime.utc(2026, 6),
        updatedAt: DateTime.utc(2026, 6, 2),
      );
      final execution = AgentActionExecution(
        id: 'exec-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 6, 11, 11),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
        requestedBy: 'hub',
        traceId: 'trace-abc',
        triggerId: 'trigger-1',
        triggerType: AgentActionTriggerType.interval,
        exitCode: 0,
        stdoutText: 'ok',
        stderrText: '',
        redactionApplied: true,
        definitionSnapshotHash: 'def-hash',
      );

      final triggerRoundTripped = mapper.triggerFromData(
        mapper.triggerToData(trigger, now: now),
      );
      final executionRoundTripped = mapper.executionFromData(
        mapper.executionToData(execution),
      );

      expect(triggerRoundTripped.id, trigger.id);
      expect(triggerRoundTripped.schedule.interval, trigger.schedule.interval);
      expect(triggerRoundTripped.schedule.weekdays, trigger.schedule.weekdays);
      expect(executionRoundTripped.id, execution.id);
      expect(executionRoundTripped.status, execution.status);
      expect(executionRoundTripped.triggerType, execution.triggerType);
      expect(executionRoundTripped.stdoutText, execution.stdoutText);
    });

    test('round-trips portable JSON for definitions and triggers', () {
      const definition = AgentActionDefinition(
        id: 'portable-action',
        name: 'Portable',
        config: CommandLineActionConfig(command: 'whoami'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(isEnabled: true, allowAdHoc: true),
        ),
      );
      const trigger = AgentActionTrigger(
        id: 'portable-trigger',
        actionId: 'portable-action',
        type: AgentActionTriggerType.remote,
        isEnabled: false,
      );

      final definitionJson = mapper.definitionToPortableJson(definition);
      final triggerJson = mapper.triggerToPortableJson(trigger);

      final roundTrippedDefinition = mapper.definitionFromPortableJson(definitionJson);
      expect(roundTrippedDefinition.id, definition.id);
      expect(roundTrippedDefinition.state, definition.state);
      expect(roundTrippedDefinition.policies.remote.isEnabled, isTrue);

      final roundTrippedTrigger = mapper.triggerFromPortableJson(triggerJson);
      expect(roundTrippedTrigger.id, trigger.id);
      expect(roundTrippedTrigger.type, trigger.type);
      expect(roundTrippedTrigger.isEnabled, trigger.isEnabled);
    });

    test('throws when config JSON is not an object', () {
      expect(
        () => mapper.definitionFromData(
          AgentActionDefinitionData(
            id: 'bad-config',
            name: 'Bad',
            type: AgentActionType.commandLine.name,
            state: AgentActionState.active.name,
            configJson: '[]',
            policiesJson: '{}',
            definitionVersion: 1,
            definitionSnapshotHash: 'hash',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
