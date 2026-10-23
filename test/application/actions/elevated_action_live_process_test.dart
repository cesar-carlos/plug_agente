import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  late Directory directory;
  final start = DateTime.utc(2026, 10, 23);
  setUp(() async => directory = await Directory.systemTemp.createTemp('elevated_live_test_'));
  tearDown(() async => directory.delete(recursive: true));

  Future<void> write(Map<String, Object?> overrides) async {
    final file = File(AgentActionElevatedConstants.statusFilePath(directory.path, 'run'));
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': AgentActionElevatedConstants.statusSchemaVersion,
        'executionId': 'run',
        'actionId': 'action',
        'status': 'running',
        'finishedAt': start.toIso8601String(),
        'processStartedAt': start.toIso8601String(),
        'pid': 42,
        'processExecutable': 'cmd.exe',
        'cpuMicroseconds': 1000,
        'cpuLimitPercent': 50,
        ...overrides,
      }),
    );
    await temp.rename(file.path);
  }

  test('publishes running identity, rejects stale CPU and clears it on completion', () async {
    final observer = _Observer();
    var now = start;
    final syncer = ElevatedActionStatusFileSyncer(
      storageContext: GlobalStorageContext(appDirectoryPath: directory.path),
      liveProcesses: observer,
      now: () => now,
    );
    await write({});
    final pending = syncer.waitForTerminalResult(
      executionId: 'run',
      processStartedAt: start,
      timeout: const Duration(seconds: 30),
    );
    final live = await observer.observed.future.timeout(const Duration(seconds: 3));
    expect(live.pid, 42);
    expect(live.executable, 'cmd.exe');
    expect(live.cpuLimitPercent, 50);
    expect(live.readCpu().getOrThrow(), const Duration(microseconds: 1000));
    now = start.add(const Duration(seconds: 4));
    expect(live.readCpu().isError(), isTrue);
    await write({'status': 'succeeded', 'exitCode': 0});
    final terminal = await pending;
    expect(terminal.getOrThrow().pid, 42);
    expect(terminal.getOrThrow().processExecutable, 'cmd.exe');
    expect(observer.finishedIds, ['run']);
    expect(observer.startedCount, 1);
  });

  test('clears live process on abort', () async {
    final observer = _Observer();
    final abort = Completer<void>();
    final signal = _CountingFuture(abort.future);
    final syncer = ElevatedActionStatusFileSyncer(
      storageContext: GlobalStorageContext(appDirectoryPath: directory.path),
      liveProcesses: observer,
    );
    await write({});
    final pending = syncer.waitForTerminalResult(
      executionId: 'run',
      processStartedAt: start,
      timeout: const Duration(seconds: 10),
      abort: signal,
    );
    await observer.observed.future;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(signal.subscriptions, 1);
    abort.complete();
    expect((await pending).isError(), isTrue);
    expect(observer.finishedIds, ['run']);
  });

  test('rejects another execution and malformed telemetry', () async {
    final syncer = ElevatedActionStatusFileSyncer(
      storageContext: GlobalStorageContext(appDirectoryPath: directory.path),
    );
    for (final values in <Map<String, Object?>>[
      {'executionId': 'other'},
      {'pid': -1},
      {'cpuMicroseconds': -1},
      {'cpuLimitPercent': 101},
      {'processStartedAt': 'invalid'},
    ]) {
      await write(values);
      expect(await syncer.tryReadStatus('run'), isNull);
    }
  });

  test('reports identity persistence failure and removes live state', () async {
    final observer = _Observer()..fail = true;
    final syncer = ElevatedActionStatusFileSyncer(
      storageContext: GlobalStorageContext(appDirectoryPath: directory.path),
      liveProcesses: observer,
    );
    await write({});
    final result = await syncer.waitForTerminalResult(
      executionId: 'run',
      processStartedAt: start,
      timeout: const Duration(seconds: 2),
    );
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).message, 'disk full');
    expect(observer.finishedIds, ['run']);
  });
}

class _Observer implements IAgentActionProcessObserver {
  final observed = Completer<AgentActionLiveProcess>();
  final List<String> finishedIds = [];
  int startedCount = 0;
  bool fail = false;
  @override
  Future<Result<void>> started(AgentActionLiveProcess process) async {
    startedCount++;
    if (!observed.isCompleted) observed.complete(process);
    return fail ? Failure(ActionRuntimeFailure('disk full')) : const Success(unit);
  }

  @override
  void finished(String executionId) => finishedIds.add(executionId);
}

class _CountingFuture implements Future<void> {
  _CountingFuture(this.source);
  final Future<void> source;
  int subscriptions = 0;
  @override
  Future<R> then<R>(FutureOr<R> Function(void) onValue, {Function? onError}) {
    subscriptions++;
    return source.then(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
