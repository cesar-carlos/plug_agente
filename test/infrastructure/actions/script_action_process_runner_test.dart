import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_process_runner.dart';

void main() {
  group('ScriptActionProcessRunner', () {
    test('should run script through default interpreter and return succeeded status', () async {
      final runner = ScriptActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(_FakeProcess(pid: 1234, exitCode: 0)),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Daily script',
          state: AgentActionState.active,
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(originalPath: r'C:\Jobs\daily.ps1'),
            arguments: <String>['-Verbose'],
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
      final runner = ScriptActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(pid: 1234, exitCode: 5, stderrText: 'script failed'),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Daily script',
          state: AgentActionState.active,
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(originalPath: r'C:\Jobs\daily.ps1'),
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
      expect(output.exitCode, 5);
      expect(output.stderr.text, 'script failed');
    });

    test('should redact captured stdout when redactBeforePersisting is enabled by default', () async {
      final runner = ScriptActionProcessRunner(
        pathValidator: _acceptingPathValidator(),
        processStarter: _starterFor(
          _FakeProcess(
            pid: 1234,
            exitCode: 0,
            stdoutText: r'ok ${secret:token} password=123',
          ),
        ),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Daily script',
          state: AgentActionState.active,
          config: ScriptActionConfig(
            scriptPath: AgentActionPathReference(originalPath: r'C:\Jobs\daily.ps1'),
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
      final runner = ScriptActionProcessRunner(
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

    group('default interpreter selection', () {
      final cases = <_InterpreterCase>[
        _InterpreterCase(
          label: 'PowerShell for .ps1',
          scriptPath: r'C:\Jobs\daily.ps1',
          expectedExecutable: 'powershell.exe',
          expectedLeadingArgs: const <String>['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File'],
          expectedScriptArgIndex: 4,
        ),
        _InterpreterCase(
          label: 'cmd.exe wrapper for .bat',
          scriptPath: r'C:\Jobs\daily.bat',
          expectedExecutable: 'cmd.exe',
          expectedLeadingArgs: const <String>['/C'],
          expectedScriptArgIndex: 1,
        ),
        _InterpreterCase(
          label: 'python.exe for .py',
          scriptPath: r'C:\Jobs\daily.py',
          expectedExecutable: 'python.exe',
          expectedLeadingArgs: const <String>[],
          expectedScriptArgIndex: 0,
        ),
      ];

      for (final scenario in cases) {
        test('should select ${scenario.label}', () async {
          late String capturedExecutable;
          late List<String> capturedArguments;
          final runner = ScriptActionProcessRunner(
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
            definition: AgentActionDefinition(
              id: 'action-1',
              name: 'Script',
              state: AgentActionState.active,
              config: ScriptActionConfig(
                scriptPath: AgentActionPathReference(originalPath: scenario.scriptPath),
              ),
            ),
            request: const AgentActionExecutionRequest(
              actionId: 'action-1',
              source: AgentActionRequestSource.localUi,
            ),
          );

          expect(result.isSuccess(), isTrue);
          expect(capturedExecutable, scenario.expectedExecutable);
          for (var index = 0; index < scenario.expectedLeadingArgs.length; index++) {
            expect(capturedArguments[index], scenario.expectedLeadingArgs[index]);
          }
          expect(capturedArguments[scenario.expectedScriptArgIndex], scenario.scriptPath);
        });
      }
    });
  });
}

class _InterpreterCase {
  const _InterpreterCase({
    required this.label,
    required this.scriptPath,
    required this.expectedExecutable,
    required this.expectedLeadingArgs,
    required this.expectedScriptArgIndex,
  });

  final String label;
  final String scriptPath;
  final String expectedExecutable;
  final List<String> expectedLeadingArgs;
  final int expectedScriptArgIndex;
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
        }) =>
            null,
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
