import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/email_action_mailer_runner.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';

void main() {
  group('EmailActionMailerRunner', () {
    test('reports a timeout even when the SMTP sender does not complete', () async {
      final pending = Completer<SendReport>();
      final runner = EmailActionMailerRunner(secretStore: _FakeSecretStore(secrets: {
        'smtp-local': '{"host":"smtp.example.com","port":587}'}),
        mailSender: (_, server, {timeout}) => pending.future);
      final result = await runner.run(executionId: 'timeout',
        definition: const AgentActionDefinition(id: 'a', name: 'Email',
          config: EmailActionConfig(smtpProfileId: 'smtp-local', from: 'agent@example.com',
            to: ['ops@example.com'], subjectTemplate: 'Subject', bodyTemplate: 'Body'),
          policies: AgentActionDefinitionPolicies(timeout: AgentActionTimeoutPolicy(maxRuntime: Duration(milliseconds: 1)))),
        request: const AgentActionExecutionRequest(actionId: 'a', source: AgentActionRequestSource.localUi));
      expect(result.exceptionOrNull(), isA<ActionTimeoutFailure>());
      expect((result.exceptionOrNull()! as ActionFailure).code, AgentActionFailureCode.executionTimedOut);
    });

    test('should send email and return succeeded process result', () async {
      Message? capturedMessage;
      SmtpServer? capturedServer;

      final runner = EmailActionMailerRunner(
        secretStore: _FakeSecretStore(
          secrets: <String, String>{
            'smtp-local': '{"host":"smtp.example.com","port":587,"username":"agent","password":"secret"}',
          },
        ),
        mailSender: (message, server, {timeout}) async {
          capturedMessage = message;
          capturedServer = server;
          final now = DateTime.utc(2026);
          return SendReport(message, now, now, now);
        },
      );

      final result = await runner.run(
        executionId: 'exec-1',
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
      final output = result.getOrThrow();
      expect(output.status, AgentActionExecutionStatus.succeeded);
      expect(output.pid, 0);
      expect(capturedMessage?.subject, 'Subject');
      expect(capturedMessage?.text, 'Body');
      expect(capturedServer?.host, 'smtp.example.com');
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
}
