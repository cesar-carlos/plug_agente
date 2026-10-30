import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

void main() {
  test('snapshot keeps I/O gauges current without mutating earlier snapshots', () {
    final collector = MetricsCollector();
    addTearDown(collector.dispose);
    final io = collector.actionIoMetrics;
    io.setQueueWaiting(2);
    io.setActiveReaders(16);
    io.setLifecycle(launches: 1, sessions: 4, cleanupUnconfirmed: false);
    final busy = collector.getSnapshot();
    io.setQueueWaiting(0);
    io.setActiveReaders(0);
    io.setLifecycle(launches: 0, sessions: 1, cleanupUnconfirmed: true);
    final draining = collector.getSnapshot();
    expect(busy['action_io_queue_waiting'], 2);
    expect(busy['action_io_readers_active'], 16);
    expect(busy['action_io_sessions_owned'], 4);
    expect(draining['action_io_queue_waiting'], 0);
    expect(draining['action_io_readers_active'], 0);
    expect(draining['action_io_readers_peak'], 16);
    expect(draining['action_io_launches_owned'], 0);
    expect(draining['action_io_sessions_owned'], 1);
    expect(draining['action_io_cleanup_unconfirmed'], 1);
  });

  test('snapshot separates unknown progress and incomplete capture from success', () {
    final collector = MetricsCollector();
    addTearDown(collector.dispose);
    final io = collector.actionIoMetrics;
    io.recordAdmittedInputBytes(6);
    io.recordPersistedOutputBytes(3);
    io.recordReadBytes(3);
    io.recordReadBytes(3);
    io.recordInputOutcome(ActionIoInputOutcome.written, confirmedBytes: 0);
    io.recordInputOutcome(ActionIoInputOutcome.unknown, confirmedBytes: null);
    io.recordInputOutcome(ActionIoInputOutcome.failed, confirmedBytes: 2);
    io.recordExecutionOutcome(ActionIoExecutionOutcome.unknown, captureComplete: false);
    io.recordRemoteOutcome(ActionIoRemoteOutcome.unauthorized);
    io.recordRemoteOutcome(ActionIoRemoteOutcome.limited);
    final snapshot = collector.getSnapshot();
    expect(snapshot['action_io_admitted_input_bytes_total'], 6);
    expect(snapshot['action_io_persisted_output_bytes_total'], 3);
    expect(snapshot['action_io_read_bytes_total'], 6);
    expect(snapshot['action_io_input_confirmed_bytes_total'], 2);
    expect(snapshot['action_io_input_unknown_progress_total'], 1);
    expect(snapshot['action_io_input_written_total'], 1);
    expect(snapshot['action_io_input_unknown_total'], 1);
    expect(snapshot['action_io_input_failed_total'], 1);
    expect(snapshot['action_io_execution_unknown_total'], 1);
    expect(snapshot['action_io_capture_incomplete_total'], 1);
    expect(snapshot['action_io_execution_succeeded_total'] ?? 0, 0);
    expect(snapshot['action_io_remote_calls_total'], 2);
    expect(snapshot['action_io_remote_unauthorized_total'], 1);
    expect(snapshot['action_io_remote_limited_total'], 1);
    final ioValues = snapshot.entries.where((entry) => entry.key.startsWith('action_io_'));
    expect(ioValues.map((entry) => entry.value), everyElement(isA<int>()));
  });
}
