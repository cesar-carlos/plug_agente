import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/command_line_action_process_runner.dart';

void main() {
  group('CommandLineActionProcessRunner', () {
    test('should run command through cmd.exe and redact captured output', () async {
      late String executable;
      late List<String> arguments;
      late String? capturedWorkingDirectory;
      final process = _FakeProcess(
        pid: 1234,
        exitCode: 0,
        stdoutText: r'ok ${secret:token} password=123',
      );
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter:
            (
              String command,
              List<String> args, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async {
              executable = command;
              arguments = args;
              capturedWorkingDirectory = workingDirectory;
              return process;
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: 'echo ok | findstr ok',
            workingDirectory: AgentActionPathReference(originalPath: r'C:\Data7'),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(executable, 'cmd.exe');
      expect(arguments, const <String>['/C', 'echo ok | findstr ok']);
      expect(capturedWorkingDirectory, r'C:\Data7');
      expect(output.pid, 1234);
      expect(output.exitCode, 0);
      expect(output.status, AgentActionExecutionStatus.succeeded);
      expect(output.processExecutable, 'cmd.exe');
      expect(output.processArgumentCount, 2);
      expect(output.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(output.processCommandPreview, isNot(contains('echo ok')));
      expect(output.stdout.text, contains('[REDACTED]'));
      expect(output.stdout.text, isNot(contains('123')));
      expect(output.redactionApplied, isTrue);
      expect(process.stdinCloseCalled, isTrue);
    });

    test('should mark failed when exit code is not accepted', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(
            pid: 1234,
            exitCode: 2,
            stderrText: 'failure',
          ),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'exit 2'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.failed);
      expect(result.getOrThrow().stderr.text, 'failure');
    });

    test('should return context hash when request has context file', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(_FakeProcess(pid: 1234, exitCode: 0)),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo ok'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          contextPath: r'C:\Temp\context.json',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().contextHash, startsWith('sha256:'));
    });

    test('should kill only main process when command times out', () async {
      final process = _FakeProcess.pendingExit(pid: 4321);
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(process),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'timeout'),
          policies: AgentActionDefinitionPolicies(
            timeout: AgentActionTimeoutPolicy(maxRuntime: Duration(milliseconds: 1)),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(process.killCalled, isTrue);
      expect(output.status, AgentActionExecutionStatus.timedOut);
      expect(output.timedOut, isTrue);
      expect(output.killed, isTrue);
      expect(output.pid, 4321);
    });

    test('should not capture output when capture policy disables it', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(
            pid: 1234,
            exitCode: 0,
            stdoutText: 'visible',
            stderrText: 'error',
          ),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo ok'),
          policies: AgentActionDefinitionPolicies(
            capture: AgentActionCapturePolicy(
              captureStdout: false,
              captureStderr: false,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(output.stdout.isCaptured, isFalse);
      expect(output.stdout.text, isEmpty);
      expect(output.stderr.isCaptured, isFalse);
      expect(output.stderr.text, isEmpty);
    });

    test('should map process start errors to runtime failure', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async {
              throw const ProcessException('cmd.exe', <String>['/C', 'missing']);
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'missing'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      final failure = result.exceptionOrNull()! as ActionRuntimeFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionProcessConstants.processStartFailedReason),
      );
      expect(failure.context, containsPair('phase', 'start_process'));
      expect(failure.context, containsPair('executable', 'cmd.exe'));
      expect(failure.context, containsPair('command_preview', 'cmd.exe /C [REDACTED_COMMAND]'));
      expect(failure.context.toString(), isNot(contains('missing')));
    });

    test('should reject execution preflight when working directory drift is detected', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: ActionPathValidator(
          fileExists: (_) async => true,
          directoryExists: (_) async => true,
          canonicalizeFile: (path) async => path,
          canonicalizeDirectory: (_) async => r'C:\Current\Jobs',
          fileLength: (_) async => 2,
          readText: (_) async => '{}',
        ),
        processStarter: _starterFor(_FakeProcess(pid: 1234, exitCode: 0)),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
              canonicalPath: r'C:\Saved\Jobs',
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.pathSnapshotMismatch);
      expect(failure.context, containsPair('phase', 'execution_preflight'));
      expect(failure.context, containsPair('reason', AgentActionPathContextConstants.pathChangedAfterSaveReason));
    });

    test('should map stdin close errors to runtime failure', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(
            pid: 1234,
            exitCode: 0,
            shouldFailStdinClose: true,
          ),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo ok'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      final failure = result.exceptionOrNull()! as ActionRuntimeFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionProcessConstants.stdinCloseFailedReason),
      );
      expect(failure.context, containsPair('phase', 'stdin_setup'));
      expect(failure.context, containsPair('executable', 'cmd.exe'));
      expect(failure.context, containsPair('command_preview', 'cmd.exe /C [REDACTED_COMMAND]'));
      expect(failure.context.toString(), isNot(contains('echo ok')));
    });

    test('should cancel active process by execution id', () async {
      final process = _FakeProcess.pendingExit(pid: 4321);
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(process),
      );

      final runFuture = runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'long-running'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final cancelResult = await runner.cancel(executionId: 'execution-1');
      final runResult = await runFuture;

      expect(cancelResult.isSuccess(), isTrue);
      expect(cancelResult.getOrThrow().pid, 4321);
      expect(cancelResult.getOrThrow().status, AgentActionExecutionStatus.killed);
      expect(process.killCalled, isTrue);
      expect(runResult.isSuccess(), isTrue);
      expect(runResult.getOrThrow().status, AgentActionExecutionStatus.killed);
    });

    test('should reject cancellation when expected pid does not match active process', () async {
      final process = _FakeProcess.pendingExit(pid: 4321);
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(process),
      );

      final runFuture = runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'long-running'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final mismatchResult = await runner.cancel(
        executionId: 'execution-1',
        expectedPid: 9999,
      );

      expect(mismatchResult.isError(), isTrue);
      expect(mismatchResult.exceptionOrNull(), isA<ActionRuntimeFailure>());
      final failure = mismatchResult.exceptionOrNull()! as ActionRuntimeFailure;
      expect(failure.code, AgentActionFailureCode.processIdMismatch);
      expect(failure.context, containsPair('reason', AgentActionProcessConstants.pidMismatchReason));
      expect(failure.context, containsPair('expected_pid', 9999));
      expect(failure.context, containsPair('actual_pid', 4321));
      expect(process.killCalled, isFalse);

      final cancelResult = await runner.cancel(
        executionId: 'execution-1',
        expectedPid: 4321,
      );
      final runResult = await runFuture;

      expect(cancelResult.isSuccess(), isTrue);
      expect(runResult.isSuccess(), isTrue);
      expect(process.killCalled, isTrue);
    });

    test('should return not active failure when canceling unknown execution', () async {
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(_FakeProcess(pid: 1234, exitCode: 0)),
      );

      final result = await runner.cancel(executionId: 'missing');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
      expect(
        (result.exceptionOrNull()! as ActionNotFoundFailure).context,
        containsPair('reason', AgentActionProcessConstants.processNotActiveReason),
      );
    });

    test('should disable parent environment inheritance in prod operational profile by default', () async {
      late bool capturedIncludeParentEnvironment;
      final runner = CommandLineActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        operationalProfileResolver: _FixedProfileResolver('prod'),
        processStarter:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool includeParentEnvironment = true,
              bool runInShell = false,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async {
              capturedIncludeParentEnvironment = includeParentEnvironment;
              return _FakeProcess(pid: 1234, exitCode: 0);
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo ok'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedIncludeParentEnvironment, isFalse);
    });
  });
}

class _FixedProfileResolver extends AgentOperationalProfileResolver {
  const _FixedProfileResolver(this._profile);

  final String _profile;

  @override
  String? get currentProfile => _profile;
}

ActionPathValidator _acceptingPathValidator() {
  return ActionPathValidator(
    fileExists: (_) async => true,
    directoryExists: (_) async => true,
    canonicalizeFile: (path) async => path,
    canonicalizeDirectory: (path) async => path,
    fileLength: (_) async => 2,
    readText: (_) async => '{}',
  );
}

AgentActionProcessStarter _starterFor(_FakeProcess process) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return process;
  };
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    required int exitCode,
    String stdoutText = '',
    String stderrText = '',
    bool shouldFailStdinClose = false,
  }) : stdout = _streamText(stdoutText),
       stderr = _streamText(stderrText),
       _stdin = _FakeIOSink(shouldFailClose: shouldFailStdinClose),
       _exitCodeCompleter = Completer<int>() {
    _exitCodeCompleter.complete(exitCode);
  }

  _FakeProcess.pendingExit({
    required this.pid,
    String stdoutText = '',
    String stderrText = '',
  }) : stdout = _streamText(stdoutText),
       stderr = _streamText(stderrText),
       _stdin = _FakeIOSink(),
       _exitCodeCompleter = Completer<int>();

  final Completer<int> _exitCodeCompleter;
  final _FakeIOSink _stdin;
  bool killCalled = false;
  bool get stdinCloseCalled => _stdin.closeCalled;

  @override
  final int pid;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  IOSink get stdin => _stdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCalled = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(-1);
    }
    return true;
  }

  static Stream<List<int>> _streamText(String value) {
    return Stream<List<int>>.fromIterable(<List<int>>[
      if (value.isNotEmpty) utf8.encode(value),
    ]);
  }
}

class _FakeIOSink implements IOSink {
  _FakeIOSink({
    this.shouldFailClose = false,
  });

  final bool shouldFailClose;
  bool closeCalled = false;

  @override
  Future<void> close() async {
    closeCalled = true;
    if (shouldFailClose) {
      throw const FileSystemException('stdin close failed');
    }
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
