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

  Future<Process> start(String command, {Map<String, String>? environment}) => WindowsSilentActionProcess.start(
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
}
