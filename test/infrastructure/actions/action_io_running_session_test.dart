import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_running_session.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';
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
  for (final mode in [
    'echo',
    'exit_rejected',
    'exit_accepted',
    'revoked',
    'timeout',
    'cancelled',
    'running_commit_failure',
    'input_receipt_failure',
    'close_receipt_failure',
    'output_commit_failure',
    'stderr_commit_failure',
    'sqlite_capacity_failure',
  ]) {
    test('running session $mode coordinates durable input output and native cleanup', () async {
      final directory = await Directory.systemTemp.createTemp('action-io-session-');
      final db = ActionIoJournalDatabase(NativeDatabase(File('${directory.path}/journal.sqlite')));
      final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 2)));
      final input = DriftActionIoJournal(db, cipher);
      final output = ActionIoOutputJournal(db, cipher);
      WindowsActionIoProcess? process;
      try {
        final bytes = List.generate(65536, (i) => i % 256);
        (await input.claim(
          const ActionIoSessionIntent(
            executionId: 'execution',
            installationId: 'installation',
            agentId: 'agent',
            clientId: 'client',
            actionId: 'action',
            idempotencyKey: 'key',
            fingerprint: 'fingerprint',
            triggerId: 'trigger',
            definitionHash: 'hash',
          ),
          // Exercise process expiry without a competing blocked-stdin timeout.
          // Uncertain native writes have their own delivery/process coverage.
          io: ActionIoConfiguration(
            closeInput: mode != 'timeout',
            initialInput: mode == 'sqlite_capacity_failure' || mode == 'timeout' ? null : bytes,
          ),
        )).getOrThrow();
        (await input.markStarting('execution')).getOrThrow();
        const echo =
            r'$i=[Console]::OpenStandardInput();$o=[Console]::OpenStandardOutput();'
            r'$b=New-Object byte[] 65536;while(($n=$i.Read($b,0,$b.Length)) -gt 0){$o.Write($b,0,$n);$o.Flush()}';
        process = (await WindowsActionIoProcess.start(
          executable: powershell,
          arguments: [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            if (mode == 'timeout')
              'Start-Sleep -Seconds 30'
            else if (mode == 'output_commit_failure' ||
                mode == 'stderr_commit_failure' ||
                mode == 'sqlite_capacity_failure')
              [
                if (mode == 'stderr_commit_failure')
                  r'$o=[Console]::OpenStandardError();'
                else
                  r'$o=[Console]::OpenStandardOutput();',
                r'$b=New-Object byte[] 65536;for($j=0;$j -lt $b.Length;$j++){$b[$j]=$j%256};',
                r'$o.Write($b,0,$b.Length);$o.Flush();',
                r'$o.Write($b,0,$b.Length);$o.Flush();Start-Sleep -Seconds 5',
              ].join(' ')
            else if (mode.startsWith('exit_'))
              '$echo; exit 7'
            else
              echo,
          ],
          controller: WindowsJobObjectProcessTreeController(api: WindowsActionJobApi()),
        )).getOrThrow();
        var authorizations = 0;
        if (mode == 'sqlite_capacity_failure') {
          (await output.append('execution', ActionIoStream.stdout, [0, 255, 26])).getOrThrow();
          final pages = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
          // Permit small terminal metadata, but not another encrypted 64 KiB block.
          await db.customStatement('PRAGMA max_page_count = ${pages + 2}');
        }
        if (mode == 'running_commit_failure') {
          await db.customStatement('''
            CREATE TRIGGER reject_running BEFORE UPDATE OF process_state ON action_io_sessions
            WHEN NEW.process_state = 'running'
            BEGIN SELECT RAISE(ABORT, 'injected running commit failure'); END
          ''');
        }
        if (mode == 'input_receipt_failure' || mode == 'close_receipt_failure') {
          final closeOnly = mode == 'close_receipt_failure' ? ' AND NEW.closes_input = 1' : '';
          await db.customStatement('''
            CREATE TRIGGER reject_written BEFORE UPDATE OF delivery_state ON action_io_messages
            WHEN NEW.delivery_state = 'written'$closeOnly
            BEGIN SELECT RAISE(ABORT, 'injected written receipt failure'); END
          ''');
        }
        if (mode == 'output_commit_failure' || mode == 'stderr_commit_failure') {
          await db.customStatement('''
            CREATE TRIGGER reject_output BEFORE INSERT ON action_io_events
            WHEN NEW.event_type = 'output' AND NEW.byte_offset > 0
            BEGIN SELECT RAISE(ABORT, 'injected output commit failure'); END
          ''');
        }
        final session = ActionIoRunningSession(
          executionId: 'execution',
          exitCodePolicy: AgentActionExitCodePolicy(acceptedExitCodes: mode == 'exit_accepted' ? {7} : {0}),
          process: process,
          inputJournal: input,
          outputJournal: output,
          deadline: DateTime.now().add(
            mode == 'timeout' ? const Duration(milliseconds: 200) : const Duration(seconds: 15),
          ),
          authorize: () async {
            authorizations++;
            if (mode == 'revoked' && authorizations >= 2) {
              return Failure(
                ActionAuthorizationFailure.withContext(message: 'Revoked.', code: 'ACTION_IO_UNAUTHORIZED'),
              );
            }
            return const Success(unit);
          },
        );
        if (mode == 'cancelled') (await session.cancel()).getOrThrow();
        final result = await session.run().timeout(const Duration(seconds: 20));
        expect(identical(session.run(), session.run()), isTrue);
        final row = await db.select(db.actionIoSessions).getSingle();
        expect(row.processState, 'finished');
        final page = (await output.read(
          executionId: 'execution',
          clientId: 'client',
          afterSequence: 0,
          maxBytes: ActionIoLimits.pageBytes,
        )).getOrThrow();
        final actual = page.events.whereType<ActionIoOutputEvent>().expand((e) => e.bytes).toList();
        if (mode == 'echo' || mode == 'exit_accepted') {
          expect(result.getOrThrow().exitCode, mode == 'exit_accepted' ? 7 : 0);
          expect(result.getOrThrow().outputComplete, isTrue);
          expect(actual, bytes);
          final receipt = (await input.inputStatus(
            'execution',
            'client',
            ActionIoLimits.initialMessageId,
          )).getOrThrow();
          expect(receipt.state, ActionIoDeliveryState.written);
          expect(receipt.confirmedBytes, bytes.length);
        } else {
          final code = switch (mode) {
            'exit_rejected' => 'ACTION_EXIT_CODE_REJECTED',
            'revoked' => 'ACTION_IO_UNAUTHORIZED',
            'cancelled' => 'ACTION_CANCELLED',
            'running_commit_failure' => 'ACTION_IO_STORAGE_FAILED',
            'input_receipt_failure' => 'ACTION_IO_STORAGE_FAILED',
            'close_receipt_failure' => 'ACTION_IO_STORAGE_FAILED',
            'output_commit_failure' => 'ACTION_IO_STORAGE_FAILED',
            'stderr_commit_failure' => 'ACTION_IO_STORAGE_FAILED',
            'sqlite_capacity_failure' => 'ACTION_IO_STORAGE_FAILED',
            _ => 'ACTION_TIMEOUT',
          };
          expect(result.isError(), isTrue);
          expect((result.exceptionOrNull()! as ActionFailure).code, code);
          expect(row.failureCode, code);
          if (mode == 'exit_rejected') {
            expect(actual, bytes);
            expect(row.exitCode, 7);
            expect(row.captureState, 'complete');
            expect((await session.runAndDrain()).isSuccess(), isTrue);
          } else if (mode == 'sqlite_capacity_failure') {
            expect(actual, [0, 255, 26]);
            expect(row.stdoutBytes, 3);
            expect(row.stderrBytes, 0);
            expect(row.captureState, 'incomplete');
            expect(page.events.whereType<ActionIoOutputEvent>(), hasLength(1));
            expect(page.events.whereType<ActionIoCompletedEvent>().single.outputComplete, isFalse);
            expect((await session.runAndDrain()).isSuccess(), isTrue);
            expect((await input.markStarting('execution')).isError(), isTrue);
            expect((await db.customSelect('PRAGMA integrity_check').getSingle()).read<String>('integrity_check'), 'ok');
          } else if (mode == 'output_commit_failure' || mode == 'stderr_commit_failure') {
            expect(actual, isNotEmpty);
            expect(actual.length, lessThanOrEqualTo(bytes.length));
            expect(actual, bytes.take(actual.length).toList());
            expect(page.events.whereType<ActionIoOutputEvent>(), hasLength(1));
            final stderr = mode == 'stderr_commit_failure';
            expect(
              page.events.whereType<ActionIoOutputEvent>().single.stream,
              stderr ? ActionIoStream.stderr : ActionIoStream.stdout,
            );
            expect(row.stdoutBytes, stderr ? 0 : actual.length);
            expect(row.stderrBytes, stderr ? actual.length : 0);
            expect(row.captureState, 'incomplete');
            expect(page.events.whereType<ActionIoCompletedEvent>().single.outputComplete, isFalse);
            expect((await session.runAndDrain()).isSuccess(), isTrue);
          } else if (mode == 'input_receipt_failure' || mode == 'close_receipt_failure') {
            // The native write completed before the receipt transaction failed;
            // termination can race output capture, so only a faithful prefix is promised.
            expect(actual.length, lessThanOrEqualTo(bytes.length));
            expect(actual, bytes.take(actual.length).toList());
            final receipt = (await input.inputStatus(
              'execution',
              'client',
              ActionIoLimits.initialMessageId,
            )).getOrThrow();
            final failedClose = mode == 'close_receipt_failure';
            expect(receipt.state, failedClose ? ActionIoDeliveryState.written : ActionIoDeliveryState.unknown);
            expect(receipt.confirmedBytes, failedClose ? bytes.length : null);
            final close = (await input.inputStatus(
              'execution',
              'client',
              ActionIoLimits.closeMessageId,
            )).getOrThrow();
            expect(close.state, failedClose ? ActionIoDeliveryState.unknown : ActionIoDeliveryState.failed);
            expect(close.confirmedBytes, failedClose ? null : 0);
            expect((await input.beginNextInput('execution')).getOrThrow().input, isNull);
            expect((await input.markStarting('execution')).isError(), isTrue);
            expect((await session.runAndDrain()).isSuccess(), isTrue);
          } else {
            expect(actual, isEmpty);
            if (mode == 'running_commit_failure') {
              expect(authorizations, 1);
              final receipt = (await input.inputStatus(
                'execution',
                'client',
                ActionIoLimits.initialMessageId,
              )).getOrThrow();
              expect(receipt.state, ActionIoDeliveryState.failed);
              expect(receipt.confirmedBytes, 0);
              expect((await session.runAndDrain()).isSuccess(), isTrue);
            }
          }
        }
        expect(process.resume().isError(), isTrue);
        expect((await session.cancel()).isSuccess(), isTrue);
      } finally {
        if (process != null) (await process.close()).getOrThrow();
        await db.close();
        await directory.delete(recursive: true);
      }
    }, skip: !Platform.isWindows);
  }
}
