import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_process_runner.dart';

import 'agent_action_process_runner_test_support.dart';

void main() {
  group('DeveloperData7ProcessRunner', () {
    test('should run Executor.exe with structured arguments', () async {
      late String executable;
      late List<String> arguments;
      late String? capturedWorkingDirectory;
      final runner = DeveloperData7ProcessRunner(
        environmentResolver: kTestActionEnvironmentResolver,
        operationalProfileResolver: kTestAgentOperationalProfileResolver,
        stdinSetup: kTestActionProcessStdinSetup,
        definitionResolver: _resolverForCatalog(),
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
              return _FakeProcess(
                pid: 5432,
                exitCode: 0,
                stdoutText: r'ok ${secret:token} senha=123',
              );
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final processResult = result.getOrThrow();
      expect(executable, r'C:\Data7\bin\Executor.exe');
      expect(arguments, <String>[
        '-p',
        r'C:\Data7\Transmissao\Transmissor.7Proj',
        '-c',
        '34512A51-672C-4ECE-9991-F43E175E7A8B',
      ]);
      expect(capturedWorkingDirectory, r'C:\Data7\bin');
      expect(processResult.status, AgentActionExecutionStatus.succeeded);
      expect(processResult.processCommandPreview, contains('Executor.exe'));
      expect(processResult.processCommandPreview, contains('.7Proj'));
      expect(processResult.stdout.text, contains('[REDACTED]'));
      expect(processResult.stdout.text, isNot(contains('123')));
    });

    test('should reject runtime parameter overrides before start', () async {
      final runner = DeveloperData7ProcessRunner(
        environmentResolver: kTestActionEnvironmentResolver,
        operationalProfileResolver: kTestAgentOperationalProfileResolver,
        stdinSetup: kTestActionProcessStdinSetup,
        definitionResolver: _resolverForCatalog(),
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {'connectionId': 'override'},
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).code,
        'DEVELOPER_DATA7_RUNTIME_PARAMETERS_NOT_SUPPORTED',
      );
    });

    test('should map process start failure with structured diagnostics', () async {
      final runner = DeveloperData7ProcessRunner(
        environmentResolver: kTestActionEnvironmentResolver,
        operationalProfileResolver: kTestAgentOperationalProfileResolver,
        stdinSetup: kTestActionProcessStdinSetup,
        definitionResolver: _resolverForCatalog(),
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
              throw const ProcessException(
                r'C:\Data7\bin\Executor.exe',
                <String>['-p', 'x', '-c', 'y'],
              );
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionRuntimeFailure>());
      final runtimeFailure = failure! as ActionRuntimeFailure;
      expect(runtimeFailure.context, containsPair('phase', 'start_process'));
      expect(runtimeFailure.context, containsPair('reason', AgentActionProcessConstants.processStartFailedReason));
      expect(runtimeFailure.context, containsPair('argument_count', 4));
      expect(runtimeFailure.context, containsPair('command_preview', contains('Executor.exe')));
    });

    test('should disable parent environment inheritance in prod operational profile by default', () async {
      late bool capturedIncludeParentEnvironment;
      final runner = DeveloperData7ProcessRunner(
        environmentResolver: kTestActionEnvironmentResolver,
        stdinSetup: kTestActionProcessStdinSetup,
        definitionResolver: _resolverForCatalog(),
        operationalProfileResolver: const _FixedProfileResolver('prod'),
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
              capturedIncludeParentEnvironment = includeParentEnvironment;
              return _FakeProcess(
                pid: 5432,
                exitCode: 0,
              );
            },
      );

      final result = await runner.run(
        executionId: 'execution-1',
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedIncludeParentEnvironment, isFalse);
    });

    test('should kill only the main process on cancel', () async {
      final processRegistered = Completer<void>();
      final process = _FakeProcess.pendingExit(pid: 4321);
      final runner = DeveloperData7ProcessRunner(
        environmentResolver: kTestActionEnvironmentResolver,
        operationalProfileResolver: kTestAgentOperationalProfileResolver,
        stdinSetup: kTestActionProcessStdinSetup,
        definitionResolver: _resolverForCatalog(),
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
              scheduleMicrotask(() {
                if (!processRegistered.isCompleted) {
                  processRegistered.complete();
                }
              });
              return process;
            },
      );

      final runFuture = runner.run(
        executionId: 'execution-1',
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await processRegistered.future;

      final cancelResult = await runner.cancel(executionId: 'execution-1');
      final runResult = await runFuture;

      expect(cancelResult.isSuccess(), isTrue);
      expect(cancelResult.getOrThrow().pid, 4321);
      expect(process.killCalled, isTrue);
      expect(runResult.isSuccess(), isTrue);
      expect(runResult.getOrThrow().status, AgentActionExecutionStatus.killed);
    });
  });
}

class _FixedProfileResolver extends AgentOperationalProfileResolver {
  const _FixedProfileResolver(this._profile);

  final String _profile;

  @override
  String? get currentProfile => _profile;
}

DeveloperData7DefinitionResolver _resolverForCatalog() {
  final pathValidator = ActionPathValidator(
    fileExists: (_) async => true,
    directoryExists: (_) async => true,
    canonicalizeFile: (path) async => path,
    canonicalizeDirectory: (path) async => path,
    fileLength: (_) async => 32,
    readText: (_) async => '{}',
    launchAccessValidator: ({required actionId, required field, required path, required phase}) => null,
  );
  return DeveloperData7DefinitionResolver(
    pathValidator: pathValidator,
    configLocator: DeveloperData7ConfigLocator(pathValidator: pathValidator),
    connectionCatalog: DeveloperData7ConnectionCatalog(
      readConfig: (_) async => '''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Estacao</Descricao>
    <Conexao>
      <Servidor>localhost</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
''',
    ),
  );
}

AgentActionDefinition _definition() {
  return AgentActionDefinition(
    id: 'action-1',
    name: 'Transmitir projeto',
    state: AgentActionState.active,
    config: DeveloperActionConfig.data7Executor(
      executorPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\bin\Executor.exe',
        canonicalPath: r'C:\Data7\bin\Executor.exe',
      ),
      projectPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        canonicalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
      ),
      data7ConfigPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\bin\Data7.Config',
        canonicalPath: r'C:\Data7\bin\Data7.Config',
      ),
      connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
      connectionLabel: 'Estacao',
    ),
  );
}

class _FakeProcess implements Process {
  _FakeProcess({
    required this.pid,
    required int exitCode,
    String stdoutText = '',
    String stderrText = '',
  }) : stdout = _streamText(stdoutText),
       stderr = _streamText(stderrText),
       _stdin = _FakeIOSink(),
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
  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
