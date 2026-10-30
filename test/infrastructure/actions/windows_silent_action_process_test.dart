import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:plug_agente/infrastructure/actions/windows_silent_action_process.dart';

void main() {
  test('delivers bounded captured prefix before a long-running process exits', () async {
    final controller = WindowsJobObjectProcessTreeController(api: WindowsActionJobApi());
    final process = await WindowsSilentActionProcess.start(
      '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
      ['/d', '/c', 'echo prefix & ping -n 30 127.0.0.1 >nul'],
      startSuspended: true,
      captureStdoutBytes: 4,
    );
    final lease = (await controller.attach(process)).getOrThrow();
    final prefix = process.stdout.first;
    try {
      (process as WindowsSilentActionProcess).resume();
      // The extra byte signals truncation without forwarding the whole output.
      expect(await prefix.timeout(const Duration(seconds: 3)), ascii.encode('prefi'));
    } finally {
      expect((await controller.release(lease)).isSuccess(), isTrue);
      await process.exitCode;
    }
  }, skip: !Platform.isWindows);

  test('fast actions stay suspended until the real Windows job protects them', () async {
    final controller = WindowsJobObjectProcessTreeController(api: WindowsActionJobApi(), cpuLimitPercent: 50);
    final process = await WindowsSilentActionProcess.start('${Platform.environment['SystemRoot']}\\System32\\cmd.exe', [
      '/d',
      '/c',
      'exit /b 7',
    ], startSuspended: true);
    var completed = false;
    process.exitCode.then((_) {
      completed = true;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(completed, isFalse);
      final lease = (await controller.attach(process)).getOrThrow();
      try {
        (process as WindowsSilentActionProcess).resume();
        expect(await process.exitCode.timeout(const Duration(seconds: 5)), 7);
      } finally {
        expect((await controller.release(lease)).isSuccess(), isTrue);
      }
    } finally {
      process.kill();
    }
  }, skip: !Platform.isWindows);

  test('structured script path and special arguments match Process.start', () async {
    final directory = await Directory.systemTemp.createTemp('plug_silent_arguments_');
    final file = File('${directory.path}/script with spaces.ps1');
    try {
      await file.writeAsString(r'''
param([string]$value)
if ($value -ceq $env:PLUG_TEST_VALUE) { exit 7 } else { exit 9 }
''');
      final executable = '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
      for (final value in ['plain', 'space & value', 'quote " value', r'trailing\']) {
        final arguments = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', file.path, value];
        final environment = {'PLUG_TEST_VALUE': value};
        final reference = await Process.run(executable, arguments, environment: environment);
        final process = await WindowsSilentActionProcess.start(executable, arguments, environment: environment);
        try {
          expect(await process.exitCode.timeout(const Duration(seconds: 10)), reference.exitCode);
        } finally {
          process.kill();
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  final powershell = '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  test('forwards at most limit plus one per stream while draining large native output', () async {
    const limit = 128;
    final process = await WindowsSilentActionProcess.start(
      powershell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$s = 'x' * 1048576; 1..8 | ForEach-Object { [Console]::Out.Write($s); [Console]::Error.Write($s) }; exit 7",
      ],
      captureStdoutBytes: limit,
      captureStderrBytes: limit,
    );
    addTearDown(process.kill);
    final output = process.stdout.expand((chunk) => chunk).toList();
    final errors = process.stderr.expand((chunk) => chunk).toList();
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 7);
    expect(await output, List.filled(limit + 1, 120));
    expect(await errors, List.filled(limit + 1, 120));
  }, skip: !Platform.isWindows);

  Future<Process> start(String command, {Map<String, String>? environment, bool requiresStdin = false}) =>
      WindowsSilentActionProcess.start(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
          base64.encode([
            for (final unit in command.codeUnits) ...[unit & 255, unit >> 8],
          ]),
        ],
        environment: environment,
        requiresStdin: requiresStdin,
      );

  test('large stdout and stderr go directly to NUL without parent pipes', () async {
    final process = await start(
      r"$s = 'x' * 1048576; 1..32 | ForEach-Object { [Console]::Out.Write($s); [Console]::Error.Write($s) }; exit 7",
    );
    addTearDown(process.kill);
    expect(await process.stdout.toList(), isEmpty);
    expect(await process.stderr.toList(), isEmpty);
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 7);
    expect(process.kill(), isFalse);
  }, skip: !Platform.isWindows);

  test('injects stdin and captures the echoed payload', () async {
    final process = await WindowsSilentActionProcess.start(
      '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
      ['/d', '/c', 'set /p value=&call echo %%value%%'],
      captureStdoutBytes: 1024,
      requiresStdin: true,
    );
    addTearDown(process.kill);
    final output = process.stdout.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    process.stdin.add(utf8.encode('native-stdin\r\n'));
    await process.stdin.flush();
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(utf8.decode(await output), contains('native-stdin'));
  }, skip: !Platform.isWindows);

  test('requiresStdin delivers EOF when closed without a payload', () async {
    final process = await start(
      'if ([Console]::In.ReadToEnd().Length -ne 0) { exit 8 }; exit 3',
      requiresStdin: true,
    );
    addTearDown(process.kill);
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 3);
  }, skip: !Platform.isWindows);

  test('delivers interactive binary blocks before the input stream closes', () async {
    const echo =
        r'$i=[Console]::OpenStandardInput(); $o=[Console]::OpenStandardOutput(); '
        r'while (($b=$i.ReadByte()) -ge 0) { $o.WriteByte([byte]$b); $o.Flush() }';
    final process = await WindowsSilentActionProcess.start(
      powershell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        echo,
      ],
      captureStdoutBytes: 1024,
      requiresStdin: true,
    );
    final source = StreamController<List<int>>();
    final received = <int>[];
    final echoed = Completer<void>();
    final subscription = process.stdout.listen((bytes) {
      received.addAll(bytes);
      if (received.length >= 6 && !echoed.isCompleted) echoed.complete();
    });
    final sending = process.stdin.addStream(source.stream);
    // Observe failure immediately; teardown still waits for ownership release.
    unawaited(sending.catchError((Object _) {}));
    try {
      source.add([0, 13, 10]);
      source.add([]);
      source.add([26, 255, 128]);
      await echoed.future.timeout(const Duration(seconds: 5));
      expect(received, [0, 13, 10, 26, 255, 128]);
      await source.close();
      await sending;
      process.stdin.add([42]);
      await process.stdin.flush();
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
    } finally {
      process.kill();
      await source.close();
      await sending.catchError((Object _) {});
      await subscription.cancel();
      await process.exitCode;
    }
  }, skip: !Platform.isWindows);

  test('a caller timeout leaves a blocked writer owned until process termination', () async {
    final process = await start('Start-Sleep -Seconds 30', requiresStdin: true);
    unawaited(process.stdin.done.catchError((Object _) {}));
    process.stdin.add(List.filled(131072, 255));
    final writing = process.stdin.flush();
    unawaited(writing.catchError((Object _) {}));
    try {
      await expectLater(writing.timeout(const Duration(milliseconds: 150)), throwsA(isA<TimeoutException>()));
      expect(process.kill(), isTrue);
      await expectLater(writing.timeout(const Duration(seconds: 5)), throwsA(isA<ProcessException>()));
      expect(await process.exitCode.timeout(const Duration(seconds: 5)), 1);
    } finally {
      process.kill();
      await writing.catchError((Object _) {});
      await process.exitCode;
    }
  }, skip: !Platform.isWindows);

  test('preserves environment values and supplies EOF on stdin', () async {
    final process = await start(
      r'''if ($env:PLUG_TEST_VALUE -ne 'space & " quote') { exit 9 }; if ([Console]::In.ReadToEnd().Length -ne 0) { exit 8 }; exit 3''',
      environment: {'PLUG_TEST_VALUE': 'space & " quote'},
    );
    addTearDown(process.kill);
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 3);
  }, skip: !Platform.isWindows);

  test('can terminate a running silent process', () async {
    final process = await start('Start-Sleep -Seconds 30');
    addTearDown(process.kill);
    expect(process.kill(), isTrue);
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 1);
  }, skip: !Platform.isWindows);

  test('missing executable fails instead of reporting a successful empty capture', () async {
    await expectLater(
      WindowsSilentActionProcess.start(r'C:\missing-plug-fixture\missing.exe', []),
      throwsA(isA<ProcessException>()),
    );
  }, skip: !Platform.isWindows);

  test('faithful capture applies backpressure and preserves both complete binary streams', () async {
    const command =
        r'$b=New-Object byte[] 256; for($i=0;$i -lt 256;$i++){$b[$i]=[byte]$i}; '
        r'$o=[Console]::OpenStandardOutput(); $e=[Console]::OpenStandardError(); '
        r'for($i=0;$i -lt 4096;$i++){$o.Write($b,0,256)}; $o.Flush(); $e.Write($b,0,256); $e.Flush()';
    final process = await WindowsSilentActionProcess.start(powershell, [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ], faithfulOutput: true);
    final native = process as WindowsSilentActionProcess;
    final first = Completer<void>();
    final completed = Completer<void>();
    final received = <int>[];
    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
      }),
    );
    final errors = process.stderr.expand((block) => block).toList();
    late StreamSubscription<List<int>> output;
    output = process.stdout.listen(
      (block) {
        expect(block.length, lessThanOrEqualTo(65536));
        received.addAll(block);
        if (!first.isCompleted) {
          output.pause();
          first.complete();
        }
      },
      onDone: completed.complete,
      onError: completed.completeError,
    );
    try {
      await first.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(exited, isFalse);
      output.resume();
      await completed.future.timeout(const Duration(seconds: 10));
      expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
      expect(received, List.generate(1048576, (index) => index % 256));
      expect(await errors, List.generate(256, (index) => index));
    } finally {
      process.kill();
      output.resume();
      await output.cancel();
      await native.closeCapturedOutput();
      await process.exitCode;
    }
  }, skip: !Platform.isWindows);
}
