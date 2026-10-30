import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/infrastructure/stores/action_io_physical_budget.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('action-io-budget-');
    path = p.join(directory.path, 'journal.sqlite');
    await File(path).writeAsBytes([1, 2, 3]);
  });
  tearDown(() => directory.delete(recursive: true));

  test('native Windows space probe admits a bounded journal without changing its files', () async {
    final budget = ActionIoPhysicalBudget(path);
    final result = await budget.checkAdmission(65536);
    expect(result.isSuccess(), isTrue, reason: '${result.exceptionOrNull()}');
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  }, skip: !Platform.isWindows);

  test('actual WAL length exhausts metadata budget without deleting retained files', () async {
    final wal = File('$path-wal');
    final handle = await wal.open(mode: FileMode.write);
    const length = ActionIoLimits.storageOverheadBytes - ActionIoPhysicalBudget.terminalReserve - 3;
    try {
      await handle.truncate(length);
      await handle.flush();
    } finally {
      await handle.close();
    }
    final budget = ActionIoPhysicalBudget(
      path,
      freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit,
    );
    expect((await budget.check(growthBytes: 0)).isSuccess(), isTrue);
    final refused = await budget.check(growthBytes: 1);
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_STORAGE_QUOTA_EXCEEDED');
    expect(await wal.length(), length);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('charges WAL duplication to overhead even when payload is retained', () async {
    await File('$path-wal').writeAsBytes([4, 5, 6]);
    final budget = ActionIoPhysicalBudget(
      path,
      freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit,
      retainedPayloadBytes: () async => 3,
    );
    const growth = ActionIoLimits.storageOverheadBytes - ActionIoPhysicalBudget.terminalReserve - 3;
    expect((await budget.check(growthBytes: growth)).isSuccess(), isTrue);
    final refused = await budget.check(growthBytes: growth + 1);
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_STORAGE_QUOTA_EXCEEDED');
    expect(await File(path).readAsBytes(), [1, 2, 3]);
    expect(await File('$path-wal').readAsBytes(), [4, 5, 6]);
  });

  test('rechecks available capacity after an earlier successful admission', () async {
    var available = ActionIoPhysicalBudget.physicalLimit;
    final budget = ActionIoPhysicalBudget(path, freeBytes: (_) async => available);
    expect((await budget.checkAdmission(65536)).isSuccess(), isTrue);
    available = ActionIoPhysicalBudget.terminalReserve;
    final refused = await budget.checkAdmission(0);
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('refuses a non-file WAL without removing the database or obstruction', () async {
    final obstruction = await Directory('$path-wal').create();
    final budget = ActionIoPhysicalBudget(path, freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit);
    final refused = await budget.checkAdmission(0);
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_STORAGE_UNAVAILABLE');
    expect(obstruction.existsSync(), isTrue);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('keeps terminal reserve and refuses unknown or insufficient available space', () async {
    for (final available in <int?>[null, -1, 0, ActionIoPhysicalBudget.terminalReserve]) {
      final result = await ActionIoPhysicalBudget(path, freeBytes: (_) async => available).check(growthBytes: 1);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect(await File(path).readAsBytes(), [1, 2, 3]);
    }
    final result = await ActionIoPhysicalBudget(
      path,
      freeBytes: (_) async => ActionIoPhysicalBudget.terminalReserve + 1,
    ).check(growthBytes: 1);
    expect(result.isSuccess(), isTrue);
  });

  test('counts database WAL and shared memory without deleting any file', () async {
    await File('$path-wal').writeAsBytes([4, 5]);
    await File('$path-shm').writeAsBytes([6]);
    final budget = ActionIoPhysicalBudget(path, freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit);
    const growth = ActionIoLimits.storageOverheadBytes - ActionIoPhysicalBudget.terminalReserve - 6;
    expect((await budget.check(growthBytes: growth)).isSuccess(), isTrue);
    final refused = await budget.check(growthBytes: growth + 1);
    expect((refused.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_STORAGE_QUOTA_EXCEEDED');
    expect(await File('$path-wal').readAsBytes(), [4, 5]);
    expect(await File('$path-shm').readAsBytes(), [6]);
  });

  test('rejects invalid payload accounting before granting physical capacity', () async {
    final budget = ActionIoPhysicalBudget(path, freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit);
    expect((await budget.checkAdmission(-1)).isError(), isTrue);
    final invalid = ActionIoPhysicalBudget(
      path,
      freeBytes: (_) async => ActionIoPhysicalBudget.physicalLimit,
      retainedPayloadBytes: () async => -1,
    );
    expect((await invalid.checkAdmission(0)).isError(), isTrue);
  });
}
