import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _MockRepository extends Mock implements IAgentActionRepository {}

class _FixedProfileResolver extends AgentOperationalProfileResolver {
  _FixedProfileResolver(this._profile);

  final String? _profile;

  @override
  String? get currentProfile => _profile;
}

void main() {
  group('AgentActionRetryPolicy', () {
    test('should default remote executions to a single attempt when allowRemote is false', () {
      const policy = AgentActionRetryPolicy(maxAttempts: 3);
      const request = AgentActionExecutionRequest(
        actionId: 'a',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'k',
      );

      expect(policy.effectiveMaxAttempts(request), 1);
    });

    test('should allow configured attempts for local executions', () {
      const policy = AgentActionRetryPolicy(maxAttempts: 3);
      const request = AgentActionExecutionRequest(
        actionId: 'a',
        source: AgentActionRequestSource.localUi,
      );

      expect(policy.effectiveMaxAttempts(request), 3);
    });

    test('should default elevated executions to a single attempt', () {
      const policy = AgentActionRetryPolicy(maxAttempts: 3);
      const request = AgentActionExecutionRequest(
        actionId: 'a',
        source: AgentActionRequestSource.localUi,
      );

      expect(policy.effectiveMaxAttempts(request, runElevated: true), 1);
    });
  });

  group('RunAgentActionLocally environment gate', () {
    test('should reject when operational profile is not allowed', () async {
      final repository = _MockRepository();
      when(() => repository.getDefinition('action-1')).thenAnswer(
        (_) async => const Success(
          AgentActionDefinition(
            id: 'action-1',
            name: 'Profile test',
            state: AgentActionState.active,
            config: CommandLineActionConfig(command: 'dir'),
            policies: AgentActionDefinitionPolicies(
              environment: AgentActionEnvironmentPolicy(
                allowedProfiles: {'prod'},
              ),
            ),
          ),
        ),
      );

      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry(const []),
        const Uuid(),
        operationalProfileResolver: _FixedProfileResolver('dev'),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.environmentProfileDenied);
      expect(failure.context['reason'], AgentActionGateConstants.environmentProfileDeniedReason);
    });

    test('should record local_authorization_denied metric when environment gate fails', () async {
      final repository = _MockRepository();
      when(() => repository.getDefinition('action-1')).thenAnswer(
        (_) async => const Success(
          AgentActionDefinition(
            id: 'action-1',
            name: 'Profile test',
            state: AgentActionState.active,
            config: CommandLineActionConfig(command: 'dir'),
            policies: AgentActionDefinitionPolicies(
              environment: AgentActionEnvironmentPolicy(
                allowedProfiles: {'prod'},
              ),
            ),
          ),
        ),
      );

      final metrics = MetricsCollector();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry(const []),
        const Uuid(),
        metrics: metrics,
        operationalProfileResolver: _FixedProfileResolver('dev'),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(metrics.getSnapshot()['agent_action_local_authorization_denied'], 1);
    });
  });
}
