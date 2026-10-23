import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';

// Compile to an executable before running. Child mode executes only this fixed
// synthetic producer. No user commands, configurations, credentials or DBs.
const int _captureBytes = 64 * 1024;
const int _floodBytes = 1024 * 1024 * 1024;

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows) throw UnsupportedError('Windows benchmark only.');
  if (arguments.length == 2 && arguments.first == '--producer') {
    await _produce(arguments.last);
    return;
  }
  if (arguments.isNotEmpty ||
      !Platform.resolvedExecutable.toLowerCase().endsWith('.exe') ||
      Platform.resolvedExecutable.toLowerCase().endsWith('dart.exe')) {
    throw ArgumentError('Compile with dart compile exe, then run the executable without arguments.');
  }
  for (final scenario in ['idle', 'stdout', 'stderr', 'both', 'stdout-disabled']) {
    for (var repetition = 0; repetition < 3; repetition++) {
      // Alternate order to reduce systematic cache/order bias.
      for (final baseline in repetition.isEven ? [true, false] : [false, true]) {
        final cpuBefore = _cpuSeconds();
        final watch = Stopwatch()..start();
        final result = await _run(scenario, baseline: baseline);
        final cpu = _cpuSeconds() - cpuBefore;
        final elapsed = watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
        final stdoutExpected = scenario == 'stdout' || scenario == 'both';
        final stderrExpected = scenario == 'stderr' || scenario == 'both';
        if (result.exitCode != 0 ||
            result.stdout.text.length != (stdoutExpected ? _captureBytes : 0) ||
            result.stderr.text.length != (stderrExpected ? _captureBytes : 0) ||
            result.stdout.isTruncated != stdoutExpected ||
            result.stderr.isTruncated != stderrExpected ||
            result.stdout.isCaptured != (scenario != 'stdout-disabled') ||
            !result.stderr.isCaptured) {
          throw StateError('Unexpected capture result: $scenario baseline=$baseline');
        }
        stdout.writeln(
          jsonEncode({
            'scenario': scenario,
            'implementation': baseline ? 'dart-pipes' : 'native-bounded',
            'repetition': repetition + 1,
            'bytesProduced': scenario == 'idle' ? 0 : _floodBytes * (scenario == 'both' ? 2 : 1),
            'retainedStdoutBytes': result.stdout.text.length,
            'retainedStderrBytes': result.stderr.text.length,
            'parentCpuSeconds': cpu,
            'elapsedSeconds': elapsed,
            'logicalProcessors': Platform.numberOfProcessors,
          }),
        );
      }
    }
  }
}

Future<void> _produce(String scenario) async {
  if (!['idle', 'stdout', 'stderr', 'both', 'stdout-disabled'].contains(scenario)) {
    throw ArgumentError.value(scenario);
  }
  // Also allows the baseline Process.start branch to attach its job first.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  if (scenario == 'idle') {
    await Future<void>.delayed(const Duration(seconds: 2));
    return;
  }
  final block = Uint8List(65536)..fillRange(0, 65536, 65);
  for (var written = 0; written < _floodBytes; written += block.length) {
    if (scenario != 'stderr') {
      stdout.add(block);
      await stdout.flush();
    }
    if (scenario == 'stderr' || scenario == 'both') {
      stderr.add(block);
      await stderr.flush();
    }
  }
}

Future<({int exitCode, AgentActionCapturedOutput stdout, AgentActionCapturedOutput stderr})> _run(
  String scenario, {
  required bool baseline,
}) async {
  final captureStdout = scenario != 'stdout-disabled';
  final process = baseline
      ? await Process.start(Platform.resolvedExecutable, ['--producer', scenario])
      : await WindowsSilentActionProcess.start(
          Platform.resolvedExecutable,
          ['--producer', scenario],
          captureStdoutBytes: captureStdout ? _captureBytes : 0,
          captureStderrBytes: _captureBytes,
        );
  ActionProcessOutputCaptureSession capture(Stream<List<int>> stream, bool enabled) =>
      ActionProcessOutputCaptureSession(
        stream,
        isEnabled: enabled,
        maxBytes: _captureBytes,
        encoding: AgentActionOutputEncodingMode.utf8,
        redactor: const AgentActionRedactor(),
        redactBeforePersisting: true,
      );
  final output = capture(process.stdout, captureStdout);
  final errors = capture(process.stderr, true);
  try {
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    return (
      exitCode: code,
      stdout: await output.result.timeout(const Duration(seconds: 5)),
      stderr: await errors.result.timeout(const Duration(seconds: 5)),
    );
  } finally {
    process.kill();
    await output.cancel();
    await errors.cancel();
  }
}

double _cpuSeconds() => using((arena) {
  final created = arena<FILETIME>();
  final exited = arena<FILETIME>();
  final kernel = arena<FILETIME>();
  final user = arena<FILETIME>();
  final measured = GetProcessTimes(GetCurrentProcess(), created, exited, kernel, user);
  if (!measured.value) throw StateError('GetProcessTimes: ${measured.error}');
  int ticks(FILETIME time) => (time.dwHighDateTime << 32) + time.dwLowDateTime;
  return (ticks(kernel.ref) + ticks(user.ref)) / 10000000;
});
