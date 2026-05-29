import 'package:checks/checks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/dtos/agent_profile_hub_sync_result.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/use_cases/sync_agent_profile_with_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';

class _MockPush extends Mock implements PushAgentProfileToHub {}

class _FakeAgentProfile extends Fake implements AgentProfile {}

void main() {
  late _MockPush push;
  late SyncAgentProfileWithHub useCase;

  setUpAll(() {
    registerFallbackValue(_FakeAgentProfile());
  });

  setUp(() {
    push = _MockPush();
    useCase = SyncAgentProfileWithHub(push);
  });

  AgentProfile buildProfile() {
    return AgentProfile.fromFormFields(
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
  }

  test('should skip sync when hub is not connected', () async {
    final result = await useCase(
      profile: buildProfile(),
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'token',
      isHubConnected: false,
    );

    check(result).equals(const AgentProfileHubSyncSkipped(AgentProfileHubSyncSkipReason.hubNotConnected));
    verifyNever(
      () => push.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    );
  });

  test('should return push failure when gateway fails', () async {
    when(
      () => push.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    ).thenAnswer(
      (_) async => Failure(domain.NetworkFailure('offline')),
    );

    final result = await useCase(
      profile: buildProfile(),
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'token',
      isHubConnected: true,
    );

    expect(result, isA<AgentProfileHubSyncPushFailed>());
  });

  test('should return succeeded when push succeeds', () async {
    when(
      () => push.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AgentHubProfilePushResult(profileVersion: 3),
      ),
    );

    final result = await useCase(
      profile: buildProfile(),
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'token',
      isHubConnected: true,
      expectedProfileVersion: 2,
    );

    expect(result, isA<AgentProfileHubSyncSucceeded>());
    check((result as AgentProfileHubSyncSucceeded).profileVersion).equals(3);
  });
}
