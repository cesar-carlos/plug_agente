import 'package:checks/checks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class _MockGateway extends Mock implements IAgentHubProfileGateway {}

void main() {
  late _MockGateway gateway;
  late PushAgentProfileToHub useCase;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    gateway = _MockGateway();
    useCase = PushAgentProfileToHub(gateway, const Uuid());
  });

  test('should forward camelCase body and return gateway success', () async {
    final profile = AgentProfile.fromFormFields(
      name: 'ACME LTDA',
      tradeName: 'ACME',
      document: '59261947000107',
      phone: '',
      mobile: '65992865050',
      email: 'a@b.com',
      street: 'Av Brasil',
      number: '130',
      district: 'Centro',
      postalCode: '78300096',
      city: 'Tangará da Serra',
      state: 'mt',
      notes: '',
      validationMessages: AgentProfileValidationMessages.english,
    ).getOrThrow();

    when(
      () => gateway.patchProfile(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AgentHubProfilePushResult(profileVersion: 7),
      ),
    );

    final result = await useCase(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'token',
      profile: profile,
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.profileVersion).equals(7);

    final captured = verify(
      () => gateway.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
        accessToken: 'token',
        body: captureAny(named: 'body'),
        idempotencyKey: captureAny(named: 'idempotencyKey'),
      ),
    ).captured;

    final body = captured[0] as Map<String, dynamic>;
    final idem = captured[1] as String?;

    check(body['tradeName']).equals('ACME');
    check((body['address'] as Map<String, dynamic>)['postalCode']).equals('78300096');
    check(body['idempotencyKey'] as String).length.equals(36);
    check(idem).isNotNull();
    check(idem!.length).equals(36);
    check(idem).equals(body['idempotencyKey'] as String);
  });

  test('should include expectedProfileVersion in body when provided', () async {
    final profile = AgentProfile.fromFormFields(
      name: 'ACME LTDA',
      tradeName: 'ACME',
      document: '59261947000107',
      phone: '',
      mobile: '65992865050',
      email: 'a@b.com',
      street: 'Av Brasil',
      number: '130',
      district: 'Centro',
      postalCode: '78300096',
      city: 'Tangará da Serra',
      state: 'mt',
      notes: '',
      validationMessages: AgentProfileValidationMessages.english,
    ).getOrThrow();

    when(
      () => gateway.patchProfile(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AgentHubProfilePushResult(profileVersion: 8),
      ),
    );

    await useCase(
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'token',
      profile: profile,
      expectedProfileVersion: 5,
    );

    final body =
        verify(
              () => gateway.patchProfile(
                serverUrl: any(named: 'serverUrl'),
                agentId: any(named: 'agentId'),
                accessToken: any(named: 'accessToken'),
                body: captureAny(named: 'body'),
                idempotencyKey: any(named: 'idempotencyKey'),
              ),
            ).captured.single
            as Map<String, dynamic>;

    check(body['expectedProfileVersion']).equals(5);
  });

  test('should propagate gateway failure', () async {
    final profile = AgentProfile.fromFormFields(
      name: 'ACME LTDA',
      tradeName: 'ACME',
      document: '59261947000107',
      phone: '',
      mobile: '65992865050',
      email: 'a@b.com',
      street: 'Av Brasil',
      number: '130',
      district: 'Centro',
      postalCode: '78300096',
      city: 'Tangará da Serra',
      state: 'mt',
      notes: '',
      validationMessages: AgentProfileValidationMessages.english,
    ).getOrThrow();

    when(
      () => gateway.patchProfile(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer(
      (_) async => Failure(domain.NetworkFailure('gateway down')),
    );

    final result = await useCase(
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'token',
      profile: profile,
    );

    check(result.isError()).isTrue();
  });
}
