import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_lifecycle.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:result_dart/result_dart.dart';

import 'agent_action_process_runner_test_support.dart';

void main() {
  group('ordinary Windows process capture', () {
    test('repeated fast exits preserve both streams without pipe failures', () async {
      for (var iteration = 0; iteration < 40; iteration++) {
        final result = (await _run('echo output&echo error 1>&2')).getOrThrow();
        expect(result.stdout.text, startsWith('output'), reason: 'iteration $iteration');
        expect(result.stderr.text, startsWith('error'), reason: 'iteration $iteration');
        expect(result.stdout.isTruncated, isFalse);
        expect(result.stderr.isTruncated, isFalse);
      }
    });

    for (final out in [true, false]) {
      for (final err in [true, false]) {
        test('independently captures and truncates stdout=$out stderr=$err', () async {
          final result = (await _run(
            'echo output&echo error 1>&2',
            capture: AgentActionCapturePolicy(captureStdout: out, captureStderr: err, maxCapturedOutputBytes: 3),
          )).getOrThrow();
          expect(result.succeeded, isTrue);
          expect(result.stdout.text, out ? 'out' : '');
          expect(result.stderr.text, err ? 'err' : '');
          expect(result.stdout.isCaptured, out);
          expect(result.stderr.isCaptured, err);
          expect(result.stdout.isTruncated, out);
          expect(result.stderr.isTruncated, err);
        });
      }
    }

    test('zero capture limit preserves enabled and truncated flags', () async {
      final result = (await _run(
        'echo output',
        capture: const AgentActionCapturePolicy(maxCapturedOutputBytes: 0),
      )).getOrThrow();
      expect(result.stdout.text, isEmpty);
      expect(result.stdout.isCaptured, isTrue);
      expect(result.stdout.isTruncated, isTrue);
      expect(result.stderr.isTruncated, isFalse);
    });

    test('exact byte limit does not report truncation and still redacts secrets', () async {
      final exact = (await _run(
        'echo abc',
        capture: const AgentActionCapturePolicy(maxCapturedOutputBytes: 5),
      )).getOrThrow();
      expect(exact.stdout.text, 'abc\r\n');
      expect(exact.stdout.isTruncated, isFalse);
      final redacted = (await _run('echo password=123')).getOrThrow();
      expect(redacted.stdout.text, contains('[REDACTED]'));
      expect(redacted.stdout.text, isNot(contains('123')));
    });

    test('captured command cannot execute before identity registration succeeds', () async {
      final folder = await Directory.systemTemp.createTemp('plug_capture_gate_');
      final marker = File('${folder.path}/marker.txt');
      final observer = _RegistrationGate();
      final running = _run('echo side-effect>marker.txt', observer: observer, workingDirectory: folder.path);
      try {
        await observer.arrived.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(marker.existsSync(), isFalse);
      } finally {
        observer.answer.complete(Failure(ActionRuntimeFailure('fixture registration refused')));
        expect((await running).isError(), isTrue);
        await folder.delete(recursive: true);
      }
    });

    test('timeout preserves already captured output while killing the process tree', () async {
      final result = (await _run(
        'echo prefix&ping -n 30 127.0.0.1 >nul',
        runtime: const Duration(seconds: 3),
      )).getOrThrow();
      expect(result.timedOut, isTrue);
      expect(result.killed, isTrue);
      expect(result.stdout.text, startsWith('prefix'));
    });

    test('stdin injection retains input and capture semantics', () async {
      final result = (await _run('set /p value=&call echo %%value%%', stdin: 'fixture-input\r\n')).getOrThrow();
      expect(result.succeeded, isTrue);
      expect(result.stdout.text, contains('fixture-input'));
    });

    test('stdin injection keeps capture bounded while stdout is flooded', () async {
      final watch = Stopwatch()..start();
      final result = (await _run(
        'set /p value=&call echo %%value%%&for /L %i in (1,1,400) do @echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        stdin: 'fixture-input\r\n',
        capture: const AgentActionCapturePolicy(maxCapturedOutputBytes: 128),
      )).getOrThrow();
      expect(result.succeeded, isTrue);
      expect(result.stdout.text, contains('fixture-input'));
      expect(result.stdout.isTruncated, isTrue);
      expect(result.stdout.text.length, lessThanOrEqualTo(128));
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    });

    test('inherited pipes cannot block completion and retain their captured prefix', () async {
      final watch = Stopwatch()..start();
      final result = (await _run(
        'echo prefix&start /b ping -n 30 127.0.0.1&exit /b 0',
        drainTimeout: const Duration(milliseconds: 200),
      )).getOrThrow();
      expect(result.succeeded, isTrue);
      expect(result.stdout.text, startsWith('prefix'));
      expect(result.stdout.isTruncated, isTrue, reason: 'stdout=${result.stdout.text} stderr=${result.stderr.text}');
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  }, skip: !Platform.isWindows);
}

Future<Result<AgentActionProcessResult>> _run(
  String command, {
  AgentActionCapturePolicy capture = const AgentActionCapturePolicy(),
  Duration runtime = const Duration(seconds: 20),
  IAgentActionProcessObserver? observer,
  String? stdin,
  String? workingDirectory,
  Duration drainTimeout = const Duration(seconds: 5),
}) {
  final lifecycle = AgentActionProcessLifecycle(
    stdinSetup: kTestActionProcessStdinSetup,
    processTreeController: WindowsJobObjectProcessTreeController(api: WindowsActionJobApi()),
    liveProcesses: observer,
    outputCaptureDrainTimeout: drainTimeout,
  );
  return lifecycle.execute(
    executionId: 'native-capture',
    definition: AgentActionDefinition(
      id: 'fixture',
      name: 'fixture',
      config: CommandLineActionConfig(command: command),
      policies: AgentActionDefinitionPolicies(
        capture: capture,
        timeout: AgentActionTimeoutPolicy(maxRuntime: runtime),
        context: AgentActionContextPolicy(
          injectionMode: stdin == null
              ? AgentActionContextInjectionMode.argument
              : AgentActionContextInjectionMode.stdin,
        ),
      ),
    ),
    request: AgentActionExecutionRequest(
      actionId: 'fixture',
      source: AgentActionRequestSource.localUi,
      runtimeParameters: {'stdin': ?stdin},
    ),
    invocation: AgentActionCommandInvocation(
      executable: '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
      arguments: ['/d', '/c', command],
      runInShell: false,
      mode: ProcessStartMode.normal,
      redactedPreview: 'synthetic fixture',
      normalizedCommandLength: command.length,
    ),
    workingDirectory: workingDirectory,
    contextHash: null,
    processEnvironment: {},
    includeParentEnvironment: true,
    startMode: ProcessStartMode.normal,
    failureMessages: const AgentActionProcessFailureMessages(
      processStartMessage: 'fixture start failed',
      processRuntimeMessage: 'fixture execution failed',
      processStartUserMessage: 'fixture start failed',
      processRuntimeUserMessage: 'fixture execution failed',
    ),
  );
}

class _RegistrationGate implements IAgentActionProcessObserver {
  final arrived = Completer<void>();
  final answer = Completer<Result<void>>();
  @override
  Future<Result<void>> started(AgentActionLiveProcess process) {
    arrived.complete();
    return answer.future;
  }

  @override
  void finished(String executionId) {}
}
