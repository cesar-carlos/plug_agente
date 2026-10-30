import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process_factory.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:win32/win32.dart';

void main() {
  final powershell = '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  WindowsJobObjectProcessTreeController controller() =>
      WindowsJobObjectProcessTreeController(api: WindowsActionJobApi());

  test('protected process preserves binary input and separate output through owned cleanup', () async {
    const script =
        r'$i=[Console]::OpenStandardInput(); $o=[Console]::OpenStandardOutput(); '
        r'$b=New-Object byte[] 65536; while(($n=$i.Read($b,0,$b.Length)) -gt 0){$o.Write($b,0,$n);$o.Flush()}; '
        r'$e=[Console]::OpenStandardError();$e.WriteByte(255);$e.Flush()';
    final process = (await WindowsActionIoProcessFactory(controller()).start(
      ActionIoInvocation(
        executable: powershell,
        arguments: [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ],
        environment: const {},
        includeParentEnvironment: true,
      ),
    )).getOrThrow();
    try {
      final output = process.stdout.expand((b) => b).toList();
      final errors = process.stderr.expand((b) => b).toList();
      process.resume().getOrThrow();
      final input = Uint8List.fromList(List.generate(65536, (i) => i % 256));
      (await process.input.write(input)).getOrThrow();
      (await process.input.close()).getOrThrow();
      expect((await process.exitCode.timeout(const Duration(seconds: 10))).getOrThrow(), 0);
      expect(process.resume().isError(), isTrue);
      expect(await output, input);
      expect(await errors, [255]);
      (await process.close()).getOrThrow();
      expect(process.resume().isError(), isTrue);
      // A late cancellation must not reuse the released native job handle.
      (await process.terminate()).getOrThrow();
      (await process.close()).getOrThrow();
    } finally {
      (await process.close()).getOrThrow();
    }
  }, skip: !Platform.isWindows);

  test('closing a suspended process never executes its action', () async {
    final process = (await WindowsActionIoProcess.start(
      executable: powershell,
      arguments: ['-NoProfile', '-Command', 'Write-Output executed'],
      controller: controller(),
    )).getOrThrow();
    final output = process.stdout.expand((b) => b).toList();
    final errors = process.stderr.expand((b) => b).toList();
    (await process.close()).getOrThrow();
    expect(await output, isEmpty);
    expect(await errors, isEmpty);
    expect(process.resume().isError(), isTrue);
  }, skip: !Platform.isWindows);

  test('terminating a non-reading process releases its blocked native writer', () async {
    final process = (await WindowsActionIoProcess.start(
      executable: powershell,
      arguments: [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$o=[Console]::OpenStandardOutput();$o.WriteByte(1);$o.Flush();Start-Sleep -Seconds 60',
      ],
      controller: controller(),
    )).getOrThrow();
    final ready = Completer<void>();
    final output = <int>[];
    final subscription = process.stdout.listen((bytes) {
      output.addAll(bytes);
      if (!ready.isCompleted) ready.complete();
    });
    final errors = process.stderr.expand((bytes) => bytes).toList();
    try {
      process.resume().getOrThrow();
      await ready.future.timeout(const Duration(seconds: 10));
      var completed = false;
      final writing = process.input.write(Uint8List(65536)).whenComplete(() => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(completed, isFalse, reason: 'The native write must actually be pending before termination.');
      (await process.terminate()).getOrThrow();
      final delivered = await writing.timeout(const Duration(seconds: 10));
      expect(delivered.isError(), isTrue);
      expect(delivered.exceptionOrNull(), isA<ActionIoPipeFailure>());
      expect((delivered.exceptionOrNull()! as ActionIoPipeFailure).code, 'ACTION_OUTCOME_UNKNOWN');
      expect((await process.exitCode.timeout(const Duration(seconds: 10))).isSuccess(), isTrue);
      expect(output, [1]);
      expect(await errors, isEmpty);
    } finally {
      (await process.close().timeout(const Duration(seconds: 10))).getOrThrow();
      await subscription.cancel();
    }
  }, skip: !Platform.isWindows);

  test('reader closing within a block preserves observed output without claiming full delivery', () async {
    const prefixLength = 1024;
    const script =
        r'$i=[Console]::OpenStandardInput();$o=[Console]::OpenStandardOutput(); '
        r'$b=New-Object byte[] 1024;$n=0;while($n -lt $b.Length){ '
        r'$r=$i.Read($b,$n,$b.Length-$n);if($r -eq 0){exit 2};$n+=$r}; '
        r'$o.Write($b,0,$n);$o.Flush();$i.Close();exit 0';
    final process = (await WindowsActionIoProcess.start(
      executable: powershell,
      arguments: [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ],
      controller: controller(),
    )).getOrThrow();
    final output = process.stdout.expand((bytes) => bytes).toList();
    final errors = process.stderr.expand((bytes) => bytes).toList();
    try {
      process.resume().getOrThrow();
      final bytes = Uint8List.fromList(List.generate(65536, (index) => index % 256));
      final result = await process.input.write(bytes).timeout(const Duration(seconds: 10));
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionIoPipeFailure;
      expect(failure.code, 'ACTION_OUTCOME_UNKNOWN');
      expect(
        failure.confirmedBytes,
        0,
        reason: 'Observed consumption is not a successful native write acknowledgement.',
      );
      expect((await process.exitCode.timeout(const Duration(seconds: 10))).getOrThrow(), 0);
      expect(await output, bytes.take(prefixLength));
      expect(await errors, isEmpty);
    } finally {
      (await process.close().timeout(const Duration(seconds: 10))).getOrThrow();
    }
  }, skip: !Platform.isWindows);

  for (final parentExits in [false, true]) {
    test('owned job closes descendant pipes when parent exits=$parentExits', () async {
      const child =
          r'$o=[Console]::OpenStandardOutput(); '
          r'$b=[Text.Encoding]::ASCII.GetBytes("$PID`n");$o.Write($b,0,$b.Length);$o.Flush(); '
          'Start-Sleep -Seconds 60';
      final encoded = base64Encode(child.codeUnits.expand((unit) => [unit & 255, unit >> 8]).toList());
      final script =
          r'$s=New-Object Diagnostics.ProcessStartInfo; '
          r'$s.FileName=$PSHOME+"\powershell.exe";$s.UseShellExecute=$false;$s.CreateNoWindow=$true; '
          '\$s.Arguments="-NoProfile -NonInteractive -EncodedCommand $encoded"; '
          r'$p=[Diagnostics.Process]::Start($s); '
          r'$o=[Console]::OpenStandardOutput();$b=[Text.Encoding]::ASCII.GetBytes("$($p.Id)`n"); '
          r'$o.Write($b,0,$b.Length);$o.Flush(); '
          '${parentExits ? "exit 0" : r"$p.WaitForExit()"}';
      final process = (await WindowsActionIoProcess.start(
        executable: powershell,
        arguments: ['-NoProfile', '-NonInteractive', '-Command', script],
        controller: controller(),
      )).getOrThrow();
      final ready = Completer<int>();
      final outputClosed = Completer<void>();
      final subscription = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (!ready.isCompleted) ready.complete(int.parse(line));
        },
        onDone: outputClosed.complete,
      );
      final errors = process.stderr.expand((bytes) => bytes).toList();
      HANDLE? childHandle;
      try {
        process.resume().getOrThrow();
        final childPid = await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () async {
            (await process.close()).getOrThrow();
            throw StateError(
              'Private descendant fixture did not signal readiness: ${utf8.decode(await errors, allowMalformed: true)}',
            );
          },
        );
        expect(childPid, isNot(process.pid));
        final opened = OpenProcess(PROCESS_ACCESS_RIGHTS(SYNCHRONIZE.toInt()), false, childPid);
        expect(opened.value.address, isNot(0));
        childHandle = opened.value;
        expect(WaitForSingleObject(childHandle, 0).value, WAIT_TIMEOUT);
        if (parentExits) {
          expect((await process.exitCode.timeout(const Duration(seconds: 10))).getOrThrow(), 0);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(WaitForSingleObject(childHandle, 0).value, WAIT_TIMEOUT);
          expect(outputClosed.isCompleted, isFalse, reason: 'The live descendant still owns stdout.');
          (await process.close().timeout(const Duration(seconds: 10))).getOrThrow();
        } else {
          (await process.terminate()).getOrThrow();
        }
        expect(WaitForSingleObject(childHandle, 10000).value, WAIT_OBJECT_0);
        await outputClosed.future.timeout(const Duration(seconds: 10));
        expect(await errors.timeout(const Duration(seconds: 10)), isEmpty);
      } finally {
        (await process.close().timeout(const Duration(seconds: 10))).getOrThrow();
        await subscription.cancel();
        if (childHandle != null) expect(CloseHandle(childHandle).value, isTrue);
      }
    }, skip: !Platform.isWindows);
  }

  test('launch errors return safe typed failure without invocation arguments', () async {
    final result = await WindowsActionIoProcess.start(
      executable: '',
      arguments: ['sensitive-fixture-value'],
      controller: controller(),
    );
    final failure = result.exceptionOrNull()! as ActionFailure;
    expect(failure.code, 'ACTION_IO_PROCESS_START_FAILED');
    expect('${failure.message} ${failure.context}', isNot(contains('sensitive-fixture-value')));
  }, skip: !Platform.isWindows);
}
