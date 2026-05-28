import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_process_runner.dart';

void main() {
  group('JarActionProcessRunner', () {
    test('should run jar through default java and return succeeded status', () async {
      final runner = JarActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(_FakeProcess(pid: 1234, exitCode: 0)),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(originalPath: r'C:\Apps\job.jar'),
            arguments: <String>['--profile', 'prod'],
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
      expect(output.exitCode, 0);
      expect(output.pid, 1234);
    });

    test('should mark failed when exit code is not in acceptedExitCodes', () async {
      final runner = JarActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(pid: 1234, exitCode: 42, stderrText: 'jar crashed'),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(originalPath: r'C:\Apps\job.jar'),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(output.status, AgentActionExecutionStatus.failed);
      expect(output.exitCode, 42);
      expect(output.stderr.text, 'jar crashed');
    });

    test('should redact captured stdout when redactBeforePersisting is enabled by default', () async {
      final runner = JarActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(
            pid: 1234,
            exitCode: 0,
            stdoutText: r'started ${secret:token} password=123',
          ),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(originalPath: r'C:\Apps\job.jar'),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(output.redactionApplied, isTrue);
      expect(output.stdout.text, contains('[REDACTED]'));
      expect(output.stdout.text, isNot(contains('123')));
    });

    test('should not call processStarter when config type is wrong', () async {
      var processStarterCalled = false;
      final runner = JarActionProcessRunner(
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
              processStarterCalled = true;
              return _FakeProcess(pid: 0, exitCode: 0);
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Wrong config',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo ok'),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(processStarterCalled, isFalse);
    });

    test('should mark timed out and kill main process when maxRuntime exceeded', () async {
      final process = _FakeProcess.pendingExit(pid: 4321);
      final runner = JarActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(process),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(originalPath: r'C:\Apps\job.jar'),
          ),
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
      expect(output.status, AgentActionExecutionStatus.timedOut);
      expect(output.timedOut, isTrue);
      expect(output.killed, isTrue);
      expect(process.killCalled, isTrue);
    });

    test('should invoke java with -jar argument and forward jar args', () async {
      late String capturedExecutable;
      late List<String> capturedArguments;
      final runner = JarActionProcessRunner(
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
              capturedExecutable = executable;
              capturedArguments = arguments;
              return _FakeProcess(pid: 1234, exitCode: 0);
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Run jar',
          state: AgentActionState.active,
          config: JarActionConfig(
            jarPath: AgentActionPathReference(originalPath: r'C:\Apps\job.jar'),
            arguments: <String>['--profile', 'prod'],
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedExecutable, 'java.exe');
      expect(capturedArguments, const <String>['-jar', r'C:\Apps\job.jar', '--profile', 'prod']);
    });
  });
}

ActionPathValidator _acceptingPathValidator() {
  return ActionPathValidator(
    fileExists: (_) async => true,
    directoryExists: (_) async => true,
    canonicalizeFile: (path) async => path,
    canonicalizeDirectory: (path) async => path,
    fileLength: (_) async => 2,
    readText: (_) async => '{}',
    launchAccessValidator:
        ({
          required String actionId,
          required String field,
          required String path,
          required String phase,
        }) => null,
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
  _FakeIOSink({this.shouldFailClose = false});

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
