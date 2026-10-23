import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_lifecycle.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_silent_action_process.dart';
import 'package:result_dart/result_dart.dart';

import 'agent_action_process_runner_test_support.dart';

void main() {
  test('publishes PID while running and removes it during failure cleanup', () async {
    final process = _Process();
    final tree = _Tree();
    final observer = _Observer();
    final running = _run(process, tree, observer: observer);
    final snapshot = await observer.arrived.future;
    expect(snapshot.pid, 123);
    expect(snapshot.actionId, 'action');
    expect(tree.released, isFalse);
    observer.answer.complete(Failure(ActionRuntimeFailure('cannot record identity')));
    expect((await running).isError(), isTrue);
    expect(observer.finishedId, 'memory-test');
    expect(tree.released, isTrue);
    expect(process.output.hasListener, isFalse);
    await process.output.close();
    await process.errors.close();
  });
  test('real Windows action with both captures disabled has no parent output pipes', () async {
    final tree = _Tree()..expectSilent = true;
    final result = await _run(_Process(), tree, capture: false, native: true);
    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow().stdout.isCaptured, isFalse);
    expect(result.getOrThrow().stderr.isCaptured, isFalse);
    expect(result.getOrThrow().exitCode, 7);
  }, skip: !Platform.isWindows);

  for (final enabled in [true, false]) {
    test('cancels held output pipes after drain timeout (capture=$enabled)', () async {
      final process = _Process();
      final tree = _Tree();
      final result = await _run(process, tree, capture: enabled);
      expect(result.isSuccess(), isTrue);
      expect(process.output.hasListener, isFalse);
      expect(process.errors.hasListener, isFalse);
      expect(result.getOrThrow().stdout.isCaptured, enabled);
      if (enabled) {
        expect(result.getOrThrow().stdout.text, 'ok');
        expect(result.getOrThrow().stdout.isTruncated, isTrue);
      }
      expect(tree.released, isTrue);
      await process.output.close();
      await process.errors.close();
    });
  }

  test('does not report success when process-tree cleanup fails', () async {
    final process = _Process();
    final tree = _Tree()..failRelease = true;
    final result = await _run(process, tree);
    expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect(result.exceptionOrNull()!.toString(), contains('cleanup failed'));
    expect(process.output.hasListener, isFalse);
    expect(process.errors.hasListener, isFalse);
    await process.output.close();
    await process.errors.close();
  });

  test('pipe errors still cancel the other pipe and release the tree', () async {
    final process = _Process()..output.addError(const FileSystemException('pipe failed'));
    final tree = _Tree();
    final result = await _run(process, tree);
    expect(result.isError(), isTrue);
    expect(tree.released, isTrue);
    expect(process.output.hasListener, isFalse);
    expect(process.errors.hasListener, isFalse);
    await process.output.close();
    await process.errors.close();
  });
}

Future<Result<AgentActionProcessResult>> _run(
  _Process process,
  _Tree tree, {
  bool capture = true,
  IAgentActionProcessObserver? observer,
  bool native = false,
}) {
  final lifecycle = AgentActionProcessLifecycle(
    stdinSetup: kTestActionProcessStdinSetup,
    liveProcesses: observer,
    outputCaptureDrainTimeout: const Duration(milliseconds: 10),
    processTreeController: tree,
    processStarter: native
        ? null
        : (
            executable,
            arguments, {
            workingDirectory,
            environment,
            includeParentEnvironment = true,
            runInShell = false,
            mode = ProcessStartMode.normal,
          }) async => process,
  );
  return lifecycle.execute(
    executionId: 'memory-test',
    definition: AgentActionDefinition(
      id: 'action',
      name: 'test',
      config: const CommandLineActionConfig(command: 'unused'),
      policies: AgentActionDefinitionPolicies(
        capture: AgentActionCapturePolicy(
          captureStdout: capture,
          captureStderr: capture,
        ),
      ),
    ),
    request: const AgentActionExecutionRequest(actionId: 'action', source: AgentActionRequestSource.localUi),
    invocation: AgentActionCommandInvocation(
      executable: native ? '${Platform.environment['SystemRoot']}\\System32\\cmd.exe' : 'unused',
      arguments: native ? ['/d', '/c', 'echo synthetic output & exit /b 7'] : [],
      runInShell: false,
      mode: ProcessStartMode.normal,
      redactedPreview: 'unused',
      normalizedCommandLength: 6,
    ),
    workingDirectory: null,
    contextHash: null,
    processEnvironment: {},
    includeParentEnvironment: false,
    startMode: ProcessStartMode.normal,
    failureMessages: const AgentActionProcessFailureMessages(
      processStartMessage: 'start failed',
      processRuntimeMessage: 'runtime failed',
      processStartUserMessage: 'start failed',
      processRuntimeUserMessage: 'runtime failed',
    ),
  );
}

class _Process implements Process {
  _Process() {
    output.add([111, 107]);
  }
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  int get pid => 123;
  @override
  Future<int> get exitCode async => 0;
  @override
  IOSink get stdin => _Sink();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements IOSink {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tree implements AgentActionProcessTreeController {
  bool expectSilent = false;
  bool failRelease = false;
  bool released = false;
  @override
  bool get requiresAttachment => false;
  @override
  Future<Result<AgentActionProcessTreeLease>> attach(Process process) async {
    if (expectSilent) expect(process, isA<WindowsSilentActionProcess>());
    return const Success(_Lease());
  }

  @override
  Future<Result<void>> terminate(AgentActionProcessTreeLease lease) async => const Success(unit);
  @override
  Future<Result<void>> release(AgentActionProcessTreeLease lease) async {
    released = true;
    return failRelease ? Failure(ActionRuntimeFailure('cleanup failed')) : const Success(unit);
  }
}

class _Lease implements AgentActionProcessTreeLease {
  const _Lease();
  @override
  bool get supportsTreeTermination => true;
}

class _Observer implements IAgentActionProcessObserver {
  final arrived = Completer<AgentActionLiveProcess>();
  final answer = Completer<Result<void>>();
  String? finishedId;
  @override
  Future<Result<void>> started(AgentActionLiveProcess process) {
    arrived.complete(process);
    return answer.future;
  }

  @override
  void finished(String executionId) {
    finishedId = executionId;
  }
}
