import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_input_delivery.dart';
import 'package:plug_agente/application/actions/action_io_output_capture.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  final powershell = '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  const intent = ActionIoSessionIntent(
    executionId: 'execution',
    installationId: 'installation',
    agentId: 'agent',
    clientId: 'client',
    actionId: 'action',
    idempotencyKey: 'key',
    fingerprint: 'fingerprint',
    triggerId: 'trigger',
    definitionHash: 'definition',
  );

  for (final exhaustQuota in [false, true]) {
    test(
      exhaustQuota
          ? 'capture quota failure preserves durable prefix and terminates the protected process'
          : 'native binary capture is durable and readable after reopening the journal',
      () async {
        final directory = await Directory.systemTemp.createTemp('plug_io_capture_');
        final file = File('${directory.path}/journal.sqlite');
        var db = ActionIoJournalDatabase(NativeDatabase(file));
        final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 7)));
        final input = DriftActionIoJournal(db, cipher);
        var journal = ActionIoOutputJournal(db, cipher);
        final controller = WindowsJobObjectProcessTreeController(api: WindowsActionJobApi());
        WindowsActionIoProcess? process;
        try {
          (await input.claim(
            intent,
            io: exhaustQuota
                ? null
                : ActionIoConfiguration(
                    closeInput: false,
                    initialInput: List.generate(65536, (i) => i % 256),
                  ),
          )).getOrThrow();
          (await input.markStarting('execution')).getOrThrow();
          if (exhaustQuota) {
            // Simulate previously admitted content without allocating 64 MiB.
            await db
                .update(db.actionIoSessions)
                .write(
                  const ActionIoSessionsCompanion(admittedInputBytes: Value(ActionIoLimits.executionBytes - 2)),
                );
          }
          const binary =
              r'$b=New-Object byte[] 256; for($i=0;$i -lt 256;$i++){$b[$i]=[byte]$i}; '
              r'$o=[Console]::OpenStandardOutput(); $e=[Console]::OpenStandardError(); '
              r'$i=[Console]::OpenStandardInput(); $buffer=New-Object byte[] 65536; '
              r'while(($n=$i.Read($buffer,0,65536)) -gt 0){$o.Write($buffer,0,$n); $o.Flush()}; '
              r'$e.Write($b,0,256); $e.Flush()';
          const overflow =
              r'$o=[Console]::OpenStandardOutput(); $o.WriteByte(1); $o.WriteByte(2); $o.Flush(); '
              r'[Console]::In.ReadLine() | Out-Null; $o.WriteByte(3); $o.Flush(); Start-Sleep -Seconds 30';
          process = (await WindowsActionIoProcess.start(
            executable: powershell,
            arguments: ['-NoProfile', '-NonInteractive', '-Command', if (exhaustQuota) overflow else binary],
            controller: controller,
          )).getOrThrow();
          var terminations = 0;
          final capture = ActionIoOutputCapture(
            executionId: 'execution',
            journal: journal,
            stdout: process.stdout,
            stderr: process.stderr,
            terminate: () async {
              terminations++;
              return process!.terminate();
            },
          );
          (await input.markRunning('execution')).getOrThrow();
          process.resume().getOrThrow();
          if (!exhaustQuota) {
            for (var sequence = 1; sequence < 4; sequence++) {
              (await input.admitInput(
                executionId: 'execution',
                clientId: 'client',
                messageId: 'message-$sequence',
                sequence: sequence,
                bytes: sequence < 2 ? List.generate(65536, (i) => i % 256) : [],
                close: sequence == 3,
              )).getOrThrow();
            }
            final delivery = ActionIoInputDelivery(
              executionId: 'execution',
              journal: input,
              pipe: process.input,
              authorize: () async => const Success(unit),
              terminate: () async {
                return process!.terminate();
              },
            );
            for (var i = 0; i < 4; i++) {
              final delivered = (await delivery.deliverNext(
                deadline: DateTime.now().add(const Duration(seconds: 10)),
              )).getOrThrow();
              expect(delivered.receipt!.state, ActionIoDeliveryState.written);
            }
            await delivery.waitForNativeCompletion();
          }
          if (exhaustQuota) {
            await db
                .select(db.actionIoEvents)
                .watch()
                .firstWhere((events) => events.isNotEmpty)
                .timeout(const Duration(seconds: 5));
            (await process.input.write(Uint8List.fromList([13, 10]))).getOrThrow();
          }
          final exitCode = (await process.exitCode.timeout(const Duration(seconds: 10))).getOrThrow();
          final captured = await capture.finishAfterExit(exitCode);
          expect(captured.isSuccess(), !exhaustQuota);
          expect(terminations, exhaustQuota ? 1 : 0);
          expect(capture.secondaryFailures, isEmpty);
          if (exhaustQuota) {
            expect((captured.exceptionOrNull()! as ActionFailure).code, 'ACTION_OUTPUT_LIMIT_EXCEEDED');
          } else {
            expect(exitCode, 0);
          }
          await capture.waitForCleanup();
          await db.close();
          db = ActionIoJournalDatabase(NativeDatabase(file));
          journal = ActionIoOutputJournal(db, cipher);
          final outputs = <int>[];
          final errors = <int>[];
          var cursor = 0;
          while (true) {
            final page = (await journal.read(
              executionId: 'execution',
              clientId: 'client',
              afterSequence: cursor,
              maxBytes: 65536,
            )).getOrThrow();
            expect(page.terminal, isTrue);
            expect(page.outputComplete, !exhaustQuota);
            for (final event in page.events.whereType<ActionIoOutputEvent>()) {
              (event.stream == ActionIoStream.stdout ? outputs : errors).addAll(event.bytes);
            }
            if (page.events.isEmpty) break;
            expect(page.nextSequence, greaterThan(cursor));
            cursor = page.nextSequence;
          }
          expect(outputs, exhaustQuota ? [1, 2] : List.generate(131072, (i) => i % 256));
          expect(errors, exhaustQuota ? isEmpty : List.generate(256, (i) => i));
        } finally {
          if (process != null) (await process.close()).getOrThrow();
          await db.close();
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );
  }
}
