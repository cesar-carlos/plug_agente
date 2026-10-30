import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';

import 'persona_chain_storage.dart' show registerChainVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('recovers interrupted native execution as unknown without replay', () async {
    final checkpointPath = Platform.environment['ACTION_IO_CRASH_CHECKPOINT'];
    if (checkpointPath == null) throw StateError('Explicit crash checkpoint is required.');
    final checkpoint = File(checkpointPath);
    final root = checkpoint.parent.resolveSymbolicLinksSync();
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    if (p.dirname(root) != temp ||
        !RegExp(r'^plug-action-io-[a-f0-9-]{36}$').hasMatch(p.basename(root)) ||
        p.basename(checkpointPath) != 'crash-checkpoint.json' ||
        checkpoint.lengthSync() > 16384) {
      throw StateError('Invalid private checkpoint.');
    }
    final data = jsonDecode(checkpoint.readAsStringSync()) as Map<String, dynamic>;
    final directory = Directory(data['directory'] as String);
    final resolved = directory.resolveSymbolicLinksSync();
    final key = data['keyName'] as String;
    if (data['format'] != 'action-io-crash-v1' ||
        p.dirname(resolved) != temp ||
        !p.basename(resolved).startsWith('action-io-launcher-') ||
        key != 'fixture_action_io_${p.basename(resolved)}') {
      throw StateError('Invalid owned journal.');
    }
    registerChainVault(directory);
    final path = p.join(resolved, 'journal.sqlite');
    if (data['kind'] == 'native-starting') {
      for (var attempt = 0; attempt < 2; attempt++) {
        final recovered = ActionIoJournalRuntime(
          path,
          keyStore: ActionIoSecureKeyStore(lockPath: '$path.key.lock', keyName: key),
        );
        try {
          (await recovered.prepare(enabled: false)).getOrThrow();
          final id = data['executionId'] as String;
          final snapshot = (await recovered.journal.getExecutionSnapshot(id)).getOrThrow();
          expect(snapshot.processState, 'unknown');
          expect(snapshot.captureState, 'incomplete');
          expect(snapshot.terminalAt, isNull);
          final receipt = (await recovered.journal.inputStatus(
            id,
            data['clientId'] as String,
            ActionIoLimits.initialMessageId,
          )).getOrThrow();
          expect(receipt.state, ActionIoDeliveryState.failed);
          expect(receipt.confirmedBytes, 0);
          expect((await recovered.journal.markStarting(id)).isError(), isTrue);
          expect((await recovered.journal.beginNextInput(id)).getOrThrow().input, isNull);
          expect((await recovered.journal.reconcileInterrupted()).getOrThrow(), 0);
        } finally {
          (await recovered.close()).getOrThrow();
        }
      }
      return;
    }
    if (data['kind'] == 'native-writing') {
      for (var attempt = 0; attempt < 2; attempt++) {
        final counters = MetricsCollector();
        final recovered = ActionIoJournalRuntime(
          path,
          metrics: counters.actionIoMetrics,
          keyStore: ActionIoSecureKeyStore(lockPath: '$path.key.lock', keyName: key),
        );
        try {
          (await recovered.prepare(enabled: false)).getOrThrow();
          final id = data['executionId'] as String;
          final state = (await recovered.journal.getExecutionSnapshot(id)).getOrThrow();
          expect(state.processState, 'unknown');
          expect(state.captureState, 'incomplete');
          expect(state.terminalAt, isNull);
          final receipt = (await recovered.journal.inputStatus(id, data['clientId'] as String, 'blocked')).getOrThrow();
          expect(receipt.state, ActionIoDeliveryState.unknown);
          expect(receipt.confirmedBytes, isNull);
          final duplicate = (await recovered.journal.admitInput(
            executionId: id,
            clientId: data['clientId'] as String,
            messageId: 'blocked',
            sequence: 0,
            bytes: List<int>.filled(65536, 65),
          )).getOrThrow();
          expect(duplicate.state, ActionIoDeliveryState.unknown);
          expect(duplicate.confirmedBytes, isNull);
          expect(
            (await recovered.journal.admitInput(
              executionId: id,
              clientId: data['clientId'] as String,
              messageId: 'new-after-restart',
              sequence: 1,
              bytes: const [0, 255],
            )).isError(),
            isTrue,
          );
          expect((await recovered.journal.beginNextInput(id)).getOrThrow().input, isNull);
          expect((await recovered.journal.markStarting(id)).isError(), isTrue);
          expect(counters.getSnapshot()[MetricsCounterNames.actionIoInterruptedExecutions] ?? 0, attempt == 0 ? 1 : 0);
        } finally {
          (await recovered.close()).getOrThrow();
        }
      }
      return;
    }
    final metrics = MetricsCollector();
    final runtime = ActionIoJournalRuntime(
      path,
      metrics: metrics.actionIoMetrics,
      keyStore: ActionIoSecureKeyStore(lockPath: '$path.key.lock', keyName: key),
    );
    try {
      (await runtime.prepare(enabled: false)).getOrThrow();
      final executionId = data['executionId'] as String;
      final snapshot = (await runtime.journal.getExecutionSnapshot(executionId)).getOrThrow();
      expect(snapshot.processState, 'unknown');
      expect(snapshot.captureState, 'incomplete');
      expect(snapshot.failureCode, 'ACTION_OUTCOME_UNKNOWN');
      expect(snapshot.terminalAt, isNull);
      final receipt = (await runtime.journal.inputStatus(
        executionId,
        data['clientId'] as String,
        ActionIoLimits.initialMessageId,
      )).getOrThrow();
      expect(receipt.state, ActionIoDeliveryState.written);
      expect(receipt.confirmedBytes, ActionIoLimits.blockBytes);
      final output = (await runtime.readLocalOutput(
        executionId: executionId,
        afterSequence: 0,
        maxBytes: ActionIoLimits.pageBytes,
      )).getOrThrow();
      expect(output.outputComplete, isFalse);
      final expected = List.generate(65536, (index) => index % 256);
      for (final stream in ActionIoStream.values) {
        expect(
          output.events
              .whereType<ActionIoOutputEvent>()
              .where((event) => event.stream == stream)
              .expand((event) => event.bytes)
              .toList(),
          expected,
        );
      }
      expect((await runtime.journal.reconcileInterrupted()).getOrThrow(), 0);
      expect((await runtime.journal.markStarting(executionId)).isError(), isTrue);
      expect((await runtime.journal.beginNextInput(executionId)).getOrThrow().input, isNull);
      final queuedId = data['queuedExecutionId'] as String;
      final queued = (await runtime.journal.getExecutionSnapshot(queuedId)).getOrThrow();
      expect(queued.processState, 'unknown');
      expect(queued.terminalAt, isNull);
      final pending = (await runtime.journal.inputStatus(queuedId, data['clientId'] as String, 'pending')).getOrThrow();
      expect(pending.state, ActionIoDeliveryState.failed);
      expect(pending.confirmedBytes, 0);
      expect((await runtime.journal.markStarting(queuedId)).isError(), isTrue);
      expect((await runtime.journal.beginNextInput(queuedId)).getOrThrow().input, isNull);
      final writingId = data['writingExecutionId'] as String;
      final uncertain = (await runtime.journal.inputStatus(
        writingId,
        data['clientId'] as String,
        'pending',
      )).getOrThrow();
      expect(uncertain.state, ActionIoDeliveryState.unknown);
      expect(uncertain.confirmedBytes, isNull);
      expect((await runtime.journal.beginNextInput(writingId)).getOrThrow().input, isNull);
      expect((await runtime.journal.markStarting(writingId)).isError(), isTrue);
      expect(metrics.getSnapshot()[MetricsCounterNames.actionIoInterruptedExecutions], 3);
      expect(metrics.getSnapshot()[MetricsCounterNames.actionIoAdmittedInputBytes] ?? 0, 0);
      expect(metrics.getSnapshot()[MetricsCounterNames.actionIoPersistedOutputBytes] ?? 0, 0);
    } finally {
      (await runtime.close()).getOrThrow();
    }
    final reopenedMetrics = MetricsCollector();
    final reopened = ActionIoJournalRuntime(
      path,
      metrics: reopenedMetrics.actionIoMetrics,
      keyStore: ActionIoSecureKeyStore(lockPath: '$path.key.lock', keyName: key),
    );
    try {
      (await reopened.prepare(enabled: false)).getOrThrow();
      final snapshot = (await reopened.journal.getExecutionSnapshot(data['executionId'] as String)).getOrThrow();
      expect(snapshot.processState, 'unknown');
      expect(snapshot.terminalAt, isNull);
      expect(reopenedMetrics.getSnapshot()[MetricsCounterNames.actionIoInterruptedExecutions] ?? 0, 0);
      expect((await reopened.journal.beginNextInput(data['executionId'] as String)).getOrThrow().input, isNull);
      final uncertain = (await reopened.journal.inputStatus(
        data['writingExecutionId'] as String,
        data['clientId'] as String,
        'pending',
      )).getOrThrow();
      expect(uncertain.state, ActionIoDeliveryState.unknown);
      expect(uncertain.confirmedBytes, isNull);
      expect((await reopened.journal.beginNextInput(data['writingExecutionId'] as String)).getOrThrow().input, isNull);
    } finally {
      (await reopened.close()).getOrThrow();
    }
  });
}
