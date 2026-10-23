import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_launch_spec.dart';
import 'package:plug_agente_elevated_runner/src/elevated_process_runner.dart';
import 'package:plug_agente_elevated_runner/src/elevated_sqlite_store.dart';
import 'package:plug_agente_elevated_runner/src/elevated_status_writer.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'elevated_process_test_',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));

  ElevatedExecutionContext context({
    bool stdout = true,
    bool stderr = true,
    int runtime = 10000,
    int maxBytes = 64,
  }) => ElevatedExecutionContext(
    executionId: 'execution',
    actionId: 'action',
    actionType: 'commandLine',
    definitionState: 'active',
    config: const {},
    policies: {
      'elevated': {'runElevated': true},
      'capture': {
        'captureStdout': stdout,
        'captureStderr': stderr,
        'maxCapturedOutputBytes': maxBytes,
      },
      'timeout': {'maxRuntimeMs': runtime},
    },
  );
  ElevatedLaunchSpec command(String text, {int cpu = 0}) => ElevatedLaunchSpec(
    executable: 'cmd.exe',
    arguments: ['/d', '/c', text],
    commandPreview: '[REDACTED]',
    cpuLimitPercent: cpu,
  );

  test('disabled capture does not retain stdout or stderr', () async {
    final result = await ElevatedProcessRunner(appDirectoryPath: directory.path)
        .run(
          context: context(stdout: false, stderr: false),
          launch: command('echo secret & echo error 1>&2'),
          materializedNonce: 'nonce',
        );
    expect(result.status, 'succeeded', reason: result.failureMessage);
    expect(result.stdoutText, isNull);
    expect(result.stderrText, isNull);
    expect(result.stdoutTruncated, isFalse);
  }, skip: !Platform.isWindows);

  test(
    'captures only the enabled stream and bounds native retention',
    () async {
      final result =
          await ElevatedProcessRunner(appDirectoryPath: directory.path).run(
            context: context(stderr: false, maxBytes: 5),
            launch: command('echo abcdefghijklmnop & echo secret 1>&2'),
            materializedNonce: 'nonce',
          );
      expect(result.status, 'succeeded', reason: result.failureMessage);
      expect(result.stdoutText, 'abcde');
      expect(result.stdoutTruncated, isTrue);
      expect(result.stderrText, isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'publishes identity and job CPU before terminal result with CPU cap',
    () async {
      final writer = _RecordingWriter(directory.path);
      final result =
          await ElevatedProcessRunner(
            appDirectoryPath: directory.path,
            statusWriter: writer,
          ).run(
            context: context(),
            launch: command(
              'ping -n 3 127.0.0.1 >nul & echo complete',
              cpu: 50,
            ),
            materializedNonce: 'nonce',
          );
      expect(result.status, 'succeeded', reason: result.failureMessage);
      expect(writer.samples.length, greaterThanOrEqualTo(2));
      final first = writer.samples.first;
      final last = writer.samples.last;
      expect(first.status, 'running');
      expect(first.pid, greaterThan(0));
      expect(first.processExecutable, 'cmd.exe');
      expect(first.cpuLimitPercent, 50);
      expect(first.cpuMicroseconds, isNotNull);
      expect(
        last.cpuMicroseconds,
        greaterThanOrEqualTo(first.cpuMicroseconds!),
      );
      expect(result.pid, first.pid);
      expect(result.processStartedAt, first.processStartedAt);
    },
    skip: !Platform.isWindows,
  );

  test('timeout terminates the tree and completes output readers', () async {
    final watch = Stopwatch()..start();
    final result = await ElevatedProcessRunner(appDirectoryPath: directory.path)
        .run(
          context: context(runtime: 300),
          launch: command('ping -n 30 127.0.0.1'),
          materializedNonce: 'nonce',
        );
    expect(result.status, 'timedOut', reason: result.failureMessage);
    expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
  }, skip: !Platform.isWindows);

  test('matching cancellation nonce stops the job', () async {
    final path = File(
      ElevatedContract.cancelFilePath(directory.path, 'execution'),
    );
    await path.parent.create(recursive: true);
    await path.writeAsString(jsonEncode({'nonce': 'nonce'}));
    final result = await ElevatedProcessRunner(appDirectoryPath: directory.path)
        .run(
          context: context(),
          launch: command('ping -n 30 127.0.0.1'),
          materializedNonce: 'nonce',
        );
    expect(result.status, 'killed', reason: result.failureMessage);
    expect(path.existsSync(), isFalse);
  }, skip: !Platform.isWindows);

  test(
    'CPU refusal fails before suspended command can create a file',
    () async {
      final marker = File('${directory.path}/must-not-exist.txt');
      final result =
          await ElevatedProcessRunner(
            appDirectoryPath: directory.path,
            jobApi: _RefusedCpu(),
          ).run(
            context: context(),
            launch: command('echo started > "${marker.path}"', cpu: 50),
            materializedNonce: 'nonce',
          );
      expect(result.status, 'failed');
      expect(result.failureMessage, contains('CPU limit'));
      expect(marker.existsSync(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test('rejects invalid CPU limit before launching a process', () async {
    var launched = false;
    final runner = ElevatedProcessRunner(
      appDirectoryPath: directory.path,
      processStarter:
          (exe, args, {workingDirectory, runInShell = false}) async {
            launched = true;
            throw StateError('must not launch');
          },
    );
    final result = await runner.run(
      context: context(),
      launch: command('echo no', cpu: 101),
      materializedNonce: 'nonce',
    );
    expect(result.status, 'failed');
    expect(result.failureMessage, contains('CPU limit'));
    expect(launched, isFalse);
    for (final value in [-1, 101, 12.5, '50']) {
      expect(
        () => ElevatedLaunchSpec.fromJson({
          'executable': 'cmd.exe',
          'arguments': [],
          'cpuLimitPercent': value,
        }),
        throwsFormatException,
      );
    }
  });
}

class _RefusedCpu extends WindowsActionJobApi {
  @override
  Win32Result<bool> configureCpu(HANDLE job, int percent) =>
      const Win32Result(value: false, error: WIN32_ERROR(50));
}

class _RecordingWriter extends ElevatedStatusWriter {
  _RecordingWriter(String path) : super(appDirectoryPath: path);
  final List<ElevatedStatusPayload> samples = [];
  @override
  Future<void> write(ElevatedStatusPayload payload) async {
    samples.add(payload);
    await super.write(payload);
  }
}
