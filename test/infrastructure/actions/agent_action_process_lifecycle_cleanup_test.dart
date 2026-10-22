import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_lifecycle.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:result_dart/result_dart.dart';

import 'agent_action_process_runner_test_support.dart';

void main() {
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

Future<Result<AgentActionProcessResult>> _run(_Process process, _Tree tree, {bool capture = true}) {
  final lifecycle = AgentActionProcessLifecycle(
    stdinSetup: kTestActionProcessStdinSetup,
    outputCaptureDrainTimeout: const Duration(milliseconds: 10),
    processTreeController: tree,
    processStarter:
        (
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
    invocation: const AgentActionCommandInvocation(
      executable: 'unused',
      arguments: [],
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
  bool failRelease = false;
  bool released = false;
  @override
  bool get requiresAttachment => false;
  @override
  Future<Result<AgentActionProcessTreeLease>> attach(Process process) async => const Success(_Lease());
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
