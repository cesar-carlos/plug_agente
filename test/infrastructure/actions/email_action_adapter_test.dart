import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/email_action_adapter.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';

void main() {
  group('EmailActionAdapter', () {
    test('should validate active email definition', () async {
      final adapter = EmailActionAdapter(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          canonicalizeFile: (_) async => r'C:\Reports\summary.pdf',
          fileLength: (_) async => 1024,
        ),
        secretStore: _FakeSecretStore(
          secrets: <String, String>{
            'smtp-local': '{"host":"smtp.example.com","port":587,"username":"agent","password":"secret"}',
          },
        ),
      );

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Notify ops',
          state: AgentActionState.active,
          config: EmailActionConfig(
            smtpProfileId: 'smtp-local',
            from: 'agent@example.com',
            to: <String>['ops@example.com'],
            subjectTemplate: 'Daily report',
            bodyTemplate: 'Report ready.',
            attachmentPaths: <AgentActionPathReference>[
              AgentActionPathReference(
                originalPath: r'C:\Reports\summary.pdf',
              ),
            ],
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().redactedDiagnostics, containsPair('recipient_count', 1));
    });

    test('should reject invalid recipient during definition validation', () async {
      final adapter = EmailActionAdapter();

      final result = await adapter.validateDefinition(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Invalid email',
          config: EmailActionConfig(
            smtpProfileId: 'smtp-local',
            from: 'agent@example.com',
            to: <String>['not-an-email'],
            subjectTemplate: 'Subject',
            bodyTemplate: 'Body',
          ),
        ),
      );

      expect(result.isError(), isTrue);
    });

    test('should prepare execution with redacted preview', () async {
      final adapter = EmailActionAdapter(
        secretStore: _FakeSecretStore(
          secrets: <String, String>{
            'smtp-local': '{"host":"smtp.example.com","port":587}',
          },
        ),
      );

      final result = await adapter.prepareExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Notify ops',
          state: AgentActionState.active,
          config: EmailActionConfig(
            smtpProfileId: 'smtp-local',
            from: 'agent@example.com',
            to: <String>['ops@example.com'],
            subjectTemplate: 'Subject',
            bodyTemplate: 'Body',
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final prepared = result.getOrThrow();
      expect(prepared.redactedCommandPreview, contains('[REDACTED]'));
      expect(prepared.redactedDiagnostics, containsPair('smtp_host', 'smtp.example.com'));
    });
  });
}

class _FakeSecretStore extends NoopAgentActionSecretStore {
  _FakeSecretStore({
    required this.secrets,
  });

  final Map<String, String> secrets;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> readSecret(String secretName) async => secrets[secretName];

  @override
  Future<bool> exists(String secretName) async => secrets.containsKey(secretName);
}
