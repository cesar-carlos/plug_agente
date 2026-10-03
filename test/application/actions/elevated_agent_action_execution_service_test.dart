import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:result_dart/result_dart.dart';

class _FakeElevatedBridge implements IElevatedActionRunnerBridge {
  _FakeElevatedBridge({required this.submitResult});

  final Result<void> submitResult;

  @override
  Future<Result<void>> submitExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    return submitResult;
  }
}

void main() {
  group('ElevatedAgentActionExecutionService', () {
    test('signals elevated helper cancellation when the absolute deadline is reached', () async {
      final canceller = _Canceller();
      final syncer = _RecordingStatusSyncer(
        result: Failure(
          ActionTimeoutFailure.withContext(message: 'Timed out', code: AgentActionFailureCode.executionTimedOut),
        ),
      );
      final start = DateTime(2026, 10, 3, 12);
      final service = ElevatedAgentActionExecutionService(
        bridge: _FakeElevatedBridge(submitResult: const Success(unit)),
        statusFileSyncer: syncer,
        readiness: ElevatedActionRunnerReadinessService(),
        canceller: canceller,
        now: () => start,
      );
      final result = await service.run(
        executionId: 'cutoff',
        definition: AgentActionDefinition(
          id: 'a',
          name: 'Elevated',
          config: const CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            timeout: AgentActionTimeoutPolicy(
              executionDeadline: start.add(const Duration(seconds: 2)),
            ),
          ),
        ),
      );
      expect(result.exceptionOrNull(), isA<ActionTimeoutFailure>());
      expect(syncer.lastTimeout, const Duration(seconds: 2));
      expect(canceller.cancelledIds, ['cutoff']);
    });

    test('should mark readiness degraded when submit fails with protection error', () async {
      final readiness = ElevatedActionRunnerReadinessService();
      final service = ElevatedAgentActionExecutionService(
        bridge: _FakeElevatedBridge(
          submitResult: Failure(
            ActionRuntimeFailure.withContext(
              message: 'Request protection failed.',
              code: AgentActionFailureCode.elevatedRequestProtectionFailed,
              context: const {
                'reason': AgentActionGateConstants.elevatedRequestProtectionFailedReason,
              },
            ),
          ),
        ),
        statusFileSyncer: ElevatedActionStatusFileSyncer(
          storageContext: const GlobalStorageContext(appDirectoryPath: '/unused'),
        ),
        readiness: readiness,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Echo',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'echo test'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );

      final result = await service.run(executionId: 'exec-1', definition: definition);

      expect(result.isError(), isTrue);
      expect(readiness.isDegraded, isTrue);
      expect(readiness.degradedReason, AgentActionFailureCode.elevatedRequestProtectionFailed);
    });

    test('should mark readiness degraded when helper reports infra failure code', () async {
      final readiness = ElevatedActionRunnerReadinessService();
      final service = ElevatedAgentActionExecutionService(
        bridge: _FakeElevatedBridge(submitResult: const Success(unit)),
        statusFileSyncer: _RecordingStatusSyncer(
          result: Success(
            AgentActionProcessResult(
              status: AgentActionExecutionStatus.failed,
              pid: 0,
              exitCode: 1,
              processStartedAt: DateTime.utc(2026, 5, 18, 14),
              finishedAt: DateTime.utc(2026, 5, 18, 14, 1),
              stdout: AgentActionCapturedOutput.disabled,
              stderr: AgentActionCapturedOutput.disabled,
              redactionApplied: true,
              failureCode: AgentActionFailureCode.elevatedRequestProtectionFailed,
              failureMessage: 'Helper could not read request.',
            ),
          ),
        ),
        readiness: readiness,
        now: () => DateTime.utc(2026, 5, 18, 14),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Echo',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'echo test'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
          timeout: AgentActionTimeoutPolicy(maxRuntime: Duration(seconds: 5)),
        ),
      );

      final result = await service.run(executionId: 'exec-2', definition: definition);

      expect(result.isSuccess(), isTrue);
      expect(readiness.isDegraded, isTrue);
      expect(readiness.degradedReason, AgentActionFailureCode.elevatedRequestProtectionFailed);
    });
  });
}

class _RecordingStatusSyncer extends ElevatedActionStatusFileSyncer {
  _RecordingStatusSyncer({required this.result})
    : super(storageContext: const GlobalStorageContext(appDirectoryPath: '/unused'));

  final Result<AgentActionProcessResult> result;
  Duration? lastTimeout;

  @override
  Future<Result<AgentActionProcessResult>> waitForTerminalResult({
    required String executionId,
    required DateTime processStartedAt,
    required Duration timeout,
    Future<void>? abort,
  }) async {
    lastTimeout = timeout;
    return result;
  }
}

class _Canceller implements IElevatedActionExecutionCanceller {
  final cancelledIds = <String>[];
  @override
  Future<Result<AgentActionCancellationResult>> cancel({required String executionId}) async {
    cancelledIds.add(executionId);
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.cancelled,
        killed: false,
      ),
    );
  }

  @override
  Future<void> cancelAllPendingExecutions() async {}
}
