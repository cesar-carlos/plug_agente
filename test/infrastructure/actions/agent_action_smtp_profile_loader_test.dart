import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_smtp_profile_loader.dart';

class _MockSecretStore extends Mock implements IAgentActionSecretStore {}

class _UnavailableSecretStore implements IAgentActionSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<String?> readSecret(String secretName) async => null;

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {}

  @override
  Future<void> deleteSecret(String secretName) async {}

  @override
  Future<bool> exists(String secretName) async => false;
}

void main() {
  group('AgentActionSmtpProfileLoader.loadProfile', () {
    test('should reject empty reference with stable reason', () async {
      const loader = AgentActionSmtpProfileLoader();

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '   ',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.invalidSmtpProfileReason);
      expect(failure.context['field'], 'smtpProfileId');
    });

    test('should parse inline JSON profile without touching store', () async {
      final store = _MockSecretStore();
      final loader = AgentActionSmtpProfileLoader(secretStore: store);

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"host":"smtp.local","port":587,"username":"ops","password":"secret","ssl":false}',
      );

      expect(result.isSuccess(), isTrue);
      final profile = result.getOrThrow();
      expect(profile.host, 'smtp.local');
      expect(profile.port, 587);
      expect(profile.username, 'ops');
      expect(profile.password, 'secret');
      expect(profile.ssl, isFalse);
      verifyNever(() => store.readSecret(any()));
    });

    test('should fail when store is unavailable and reference is not inline JSON', () async {
      final loader = AgentActionSmtpProfileLoader(secretStore: _UnavailableSecretStore());

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: 'smtp-prod',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionRuntimeFailure;
      expect(failure.context['reason'], AgentActionValidationConstants.secretStoreUnavailableReason);
      expect(failure.code, AgentActionFailureCode.secretUnavailable);
    });

    test('should fail when store returns null with smtp_profile_not_found reason', () async {
      final store = _MockSecretStore();
      when(() => store.isAvailable).thenReturn(true);
      when(() => store.readSecret('smtp-prod')).thenAnswer((_) async => null);

      final loader = AgentActionSmtpProfileLoader(secretStore: store);

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: 'smtp-prod',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionRuntimeFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.smtpProfileNotFoundReason);
      expect(failure.context['secret_name'], 'smtp-prod');
    });

    test('should parse profile loaded from store', () async {
      final store = _MockSecretStore();
      when(() => store.isAvailable).thenReturn(true);
      when(() => store.readSecret('smtp-prod')).thenAnswer(
        (_) async => '{"host":"mail.example.com","port":465,"ssl":true}',
      );

      final loader = AgentActionSmtpProfileLoader(secretStore: store);

      final profile = (await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: 'smtp-prod',
      )).getOrThrow();

      expect(profile.host, 'mail.example.com');
      expect(profile.port, 465);
      expect(profile.ssl, isTrue);
      expect(profile.username, isNull);
      expect(profile.password, isNull);
    });

    test('should reject JSON without host with invalid_smtp_profile reason', () async {
      const loader = AgentActionSmtpProfileLoader();

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"port":587}',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['field'], 'smtpProfileId.host');
      expect(failure.context['reason'], AgentActionEmailConstants.invalidSmtpProfileReason);
    });

    test('should reject JSON with invalid port (string or out of range)', () async {
      const loader = AgentActionSmtpProfileLoader();

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"host":"x","port":"abc"}',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['field'], 'smtpProfileId.port');
    });

    test('should accept string port that parses to a valid integer', () async {
      const loader = AgentActionSmtpProfileLoader();

      final profile = (await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"host":"x","port":"2525"}',
      )).getOrThrow();

      expect(profile.port, 2525);
    });

    test('should map malformed JSON to ActionValidationFailure with cause', () async {
      const loader = AgentActionSmtpProfileLoader();

      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"host":',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.invalidSmtpProfileReason);
    });

    test('should reject JSON top-level that is not a map', () async {
      const loader = AgentActionSmtpProfileLoader();

      // Reference must start with `{` to enter JSON parsing branch.
      final result = await loader.loadProfile(
        actionId: 'a-1',
        smtpProfileReference: '{"@kind":"array"}',
      );

      // Has host? No -> rejected with invalid_smtp_profile
      expect(result.isError(), isTrue);
    });
  });
}
