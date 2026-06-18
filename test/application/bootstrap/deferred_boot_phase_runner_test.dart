import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner_dependencies.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

class _FakeAgentActionsBootPhases implements AgentActionsBootPhasesContract {
  _FakeAgentActionsBootPhases({
    this.onDeferredMaintenance,
    this.onStartScheduler,
    this.throwOnDeferredMaintenance = false,
    this.schedulerStarted = true,
  });

  final Future<void> Function()? onDeferredMaintenance;
  final Future<void> Function()? onStartScheduler;
  final bool throwOnDeferredMaintenance;
  final bool schedulerStarted;

  @override
  Future<void> runCritical() async {}

  @override
  Future<void> runDeferredMaintenance() async {
    if (throwOnDeferredMaintenance) {
      throw StateError('boom');
    }
    await onDeferredMaintenance?.call();
  }

  @override
  Future<bool> startSchedulerAndDispatchAppStart() async {
    await onStartScheduler?.call();
    return schedulerStarted;
  }
}

class _MockActiveConfigResolver extends Mock implements ActiveConfigResolver {}

class _MockConnectionStringSource extends Mock implements IConfigConnectionStringSource {}

class _WarmUpConnectionPool extends Mock implements IConnectionPool, IConnectionPoolWarmUp {}

class _FakeAutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  int startAutomaticChecksCallCount = 0;

  @override
  bool isAvailable = true;

  @override
  bool automaticSilentUpdatesEnabled = false;

  @override
  bool updateNotificationsEnabled = false;

  @override
  bool isSilentCheckInProgress = false;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => false;

  @override
  bool hasUpdateAwaitingUserConsent = false;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> startAutomaticChecks() async {
    startAutomaticChecksCallCount += 1;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_sampleConfig());
  });

  group('DeferredBootPhaseRunner', () {
    late AgentActionRuntimeStateGuard runtimeStateGuard;

    setUp(() {
      runtimeStateGuard = AgentActionRuntimeStateGuard()..markStarting(reason: 'boot');
    });

    DeferredBootPhaseRunner createRunner(
      AgentActionsBootPhasesContract bootPhases, {
      DeferredBootPhaseRunnerDependencies? dependencies,
      RuntimeCapabilities? capabilities,
    }) {
      return DeferredBootPhaseRunner(
        agentActionsBootPhases: bootPhases,
        dependencies:
            dependencies ??
            DeferredBootPhaseRunnerDependencies(
              runtimeStateGuard: runtimeStateGuard,
            ),
        capabilities: capabilities,
      );
    }

    test('marks runtime guard ready only after deferred phases complete', () async {
      final callOrder = <String>[];
      final runner = createRunner(
        _FakeAgentActionsBootPhases(
          onDeferredMaintenance: () async {
            callOrder.add('deferred');
            expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.starting);
          },
          onStartScheduler: () async {
            callOrder.add('scheduler');
            expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.starting);
          },
        ),
      );

      final outcome = await runner.run();

      expect(callOrder, <String>['deferred', 'scheduler']);
      expect(outcome.agentActionsFullyReady, isTrue);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.ready);
    });

    test('runs maintenance before scheduler and pool warm-up', () async {
      final callOrder = <String>[];
      final configResolver = _MockActiveConfigResolver();
      final connectionStringSource = _MockConnectionStringSource();
      final pool = _WarmUpConnectionPool();
      final config = _sampleConfig();

      when(configResolver.resolveActiveForDatabaseAccess).thenAnswer(
        (_) async => Success(config),
      );
      when(() => connectionStringSource.resolveConnectionString(config)).thenReturn('dsn=local');
      when(() => pool.warmUp('dsn=local', warmUpCount: any(named: 'warmUpCount'))).thenAnswer(
        (_) async => const Success(unit),
      );

      final runner = createRunner(
        _FakeAgentActionsBootPhases(
          onDeferredMaintenance: () async {
            callOrder.add('maintenance');
          },
          onStartScheduler: () async {
            callOrder.add('scheduler');
          },
        ),
        dependencies: DeferredBootPhaseRunnerDependencies(
          runtimeStateGuard: runtimeStateGuard,
          activeConfigResolver: configResolver,
          connectionStringSource: connectionStringSource,
          connectionPool: pool,
        ),
      );

      await runner.run();

      expect(callOrder, <String>['maintenance', 'scheduler']);
      verify(() => pool.warmUp('dsn=local', warmUpCount: any(named: 'warmUpCount'))).called(1);
    });

    test('warms up connection pool when dependencies support warm-up', () async {
      final configResolver = _MockActiveConfigResolver();
      final connectionStringSource = _MockConnectionStringSource();
      final pool = _WarmUpConnectionPool();
      final config = _sampleConfig();

      when(configResolver.resolveActiveForDatabaseAccess).thenAnswer(
        (_) async => Success(config),
      );
      when(() => connectionStringSource.resolveConnectionString(config)).thenReturn('dsn=warm');
      when(() => pool.warmUp('dsn=warm', warmUpCount: any(named: 'warmUpCount'))).thenAnswer(
        (_) async => const Success(unit),
      );

      final runner = createRunner(
        _FakeAgentActionsBootPhases(),
        dependencies: DeferredBootPhaseRunnerDependencies(
          runtimeStateGuard: runtimeStateGuard,
          activeConfigResolver: configResolver,
          connectionStringSource: connectionStringSource,
          connectionPool: pool,
        ),
      );

      await runner.run();

      verify(() => pool.warmUp('dsn=warm', warmUpCount: any(named: 'warmUpCount'))).called(1);
    });

    test('skips auto-update when capabilities disallow it', () async {
      final orchestrator = _FakeAutoUpdateOrchestrator();
      final runner = createRunner(
        _FakeAgentActionsBootPhases(),
        dependencies: DeferredBootPhaseRunnerDependencies(
          runtimeStateGuard: runtimeStateGuard,
          autoUpdateOrchestrator: orchestrator,
        ),
        capabilities: RuntimeCapabilities.degraded(
          reasons: const ['legacy windows'],
        ),
      );

      await runner.run();

      expect(orchestrator.startAutomaticChecksCallCount, 0);
    });

    test('starts auto-update when capabilities allow it', () async {
      final orchestrator = _FakeAutoUpdateOrchestrator();
      final runner = createRunner(
        _FakeAgentActionsBootPhases(),
        dependencies: DeferredBootPhaseRunnerDependencies(
          runtimeStateGuard: runtimeStateGuard,
          autoUpdateOrchestrator: orchestrator,
        ),
        capabilities: RuntimeCapabilities.full(),
      );

      await runner.run();

      expect(orchestrator.startAutomaticChecksCallCount, 1);
    });

    test('marks runtime guard disabled when deferred phases throw before scheduler', () async {
      final runner = createRunner(
        _FakeAgentActionsBootPhases(
          throwOnDeferredMaintenance: true,
        ),
      );

      final outcome = await runner.run();

      expect(outcome.hadCriticalFailure, isTrue);
      expect(outcome.shouldSkipHubAutoConnect, isTrue);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.disabled);
    });

    test('marks runtime guard degraded when scheduler does not start', () async {
      final runner = createRunner(
        _FakeAgentActionsBootPhases(
          schedulerStarted: false,
        ),
      );

      final outcome = await runner.run();

      expect(outcome.hadCriticalFailure, isFalse);
      expect(outcome.schedulerStarted, isFalse);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.degraded);
    });
  });
}

Config _sampleConfig() {
  final now = DateTime.utc(2026);
  return Config(
    id: 'config-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 18 for SQL Server',
    connectionString: 'dsn=local',
    username: 'user',
    databaseName: 'db',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );
}
