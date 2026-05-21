import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';

void main() {
  late AgentActionBackupSanitizer sanitizer;

  setUp(() {
    sanitizer = AgentActionBackupSanitizer(
      codec: const AgentActionPortableCodec(),
      now: () => DateTime.utc(2026, 5, 18, 12),
    );
  });

  AgentActionDefinition buildDefinition({
    String command = r'cmd.exe /C echo password=secret123 token=${secret:db_pass}',
    AgentActionRemotePolicy? remote,
  }) {
    return AgentActionDefinition(
      id: 'action-1',
      name: 'Backup test',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: command),
      policies: AgentActionDefinitionPolicies(
        remote:
            remote ??
            AgentActionRemotePolicy(
              isEnabled: true,
              allowAdHoc: true,
              approvedBy: 'admin@example.com',
              approvedAt: DateTime.utc(2026),
              approvalReason: 'approved in prod',
              riskFingerprint: 'abc123',
            ),
      ),
    );
  }

  test('should preserve secret placeholders and redact literal secrets on export', () {
    final exported = sanitizer.sanitizeDefinitionForExport(buildDefinition());
    final config = exported['config']! as Map<String, Object?>;
    final command = config['command']! as String;

    expect(command, contains(r'${secret:db_pass}'));
    expect(command, isNot(contains('secret123')));
    expect(command, contains(AgentActionBackupConstants.sanitizedLiteralReplacement));
  });

  test('should strip remote approval metadata and pause triggers on export', () {
    final definitionExport = sanitizer.sanitizeDefinitionForExport(buildDefinition());
    final remote = (definitionExport['policies']! as Map)['remote']! as Map;
    expect(remote['isEnabled'], isFalse);
    expect(remote['requiresReapproval'], isTrue);
    expect(remote, isNot(contains('approvedBy')));
    expect(remote, isNot(contains('approvedAt')));
    expect(remote, isNot(contains('approvalReason')));
    expect(remote, isNot(contains('riskFingerprint')));

    const trigger = AgentActionTrigger(
      id: 'trigger-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      schedule: AgentActionTriggerSchedule(
        timeOfDayMinutes: 9 * 60,
        timezoneId: 'America/Sao_Paulo',
      ),
    );
    final triggerExport = sanitizer.sanitizeTriggerForExport(trigger);
    expect(triggerExport['isEnabled'], isFalse);
    expect(triggerExport['export_note'], isNotNull);
  });

  test('should prepare imported definitions for revalidation with remote disabled', () {
    final bundle = sanitizer.buildExportBundle(
      definitions: [buildDefinition()],
      triggers: const [],
    );
    final definitionJson = (bundle['definitions']! as List).first as Map<String, Object?>;

    final imported = sanitizer.prepareDefinitionForImport(definitionJson);

    expect(imported.state, AgentActionState.needsValidation);
    expect(imported.policies.remote.isEnabled, isFalse);
    expect(imported.policies.remote.requiresReapproval, isTrue);
    expect(imported.policies.remote.approvedBy, isNull);
  });

  test('should list secret placeholder names referenced in export bundle', () {
    final bundle = sanitizer.buildExportBundle(
      definitions: [buildDefinition()],
      triggers: const [],
    );

    expect(bundle['export_schema'], AgentActionBackupConstants.exportSchemaV1);
    expect(bundle['secret_placeholders_referenced'], contains('db_pass'));
    expect(sanitizer.secretPlaceholdersInBundle(bundle), contains('db_pass'));
  });

  test('should round-trip portable config through codec after import preparation', () {
    final original = buildDefinition(command: r'echo ${secret:api_key}');
    final exported = sanitizer.sanitizeDefinitionForExport(original);
    final imported = sanitizer.prepareDefinitionForImport(exported);

    expect(
      (imported.config as CommandLineActionConfig).command,
      contains(r'${secret:api_key}'),
    );
  });
}
