import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/infrastructure/actions/action_io_file_export.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  late Directory directory;
  late File destination;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('action-io-export-test-');
    destination = File(p.join(directory.path, 'stdout.bin'));
    await destination.writeAsBytes([7]);
  });
  tearDown(() => directory.delete(recursive: true));
  test('denied admission never produces or stages output', () async {
    var produced = false;
    final denied = ActionRuntimeFailure.withContext(message: 'Export denied.', code: 'EXPORT_DENIED');
    final result = await const ActionIoFileExport().save(
      destination.path,
      (write) async {
        produced = true;
        return const Success(ActionIoExportSummary(bytes: 0, outputComplete: true, terminal: true));
      },
      authorize: () async => Failure(denied),
    );
    expect(result.exceptionOrNull(), same(denied));
    expect(produced, isFalse);
    expect(await destination.readAsBytes(), [7]);
    expect(await directory.list().toList(), hasLength(1));
  });
  test('publishes exact binary bytes only after all writes succeed', () async {
    final result = await const ActionIoFileExport().save(destination.path, (write) async {
      (await write([0, 255, 13, 10])).getOrThrow();
      expect(await destination.readAsBytes(), [7]);
      (await write([26, 128])).getOrThrow();
      return const Success(ActionIoExportSummary(bytes: 6, outputComplete: false, terminal: true));
    }, authorize: () async => const Success(unit));
    expect(result.getOrThrow().outputComplete, isFalse);
    expect(await destination.readAsBytes(), [0, 255, 13, 10, 26, 128]);
    expect(await directory.list().toList(), hasLength(1));
  });
  test('producer failure preserves destination and removes temporary payload', () async {
    final failure = ActionRuntimeFailure.withContext(message: 'Read failed.', code: 'OUTPUT_EXPIRED');
    final result = await const ActionIoFileExport().save(destination.path, (write) async {
      (await write([65])).getOrThrow();
      return Failure(failure);
    }, authorize: () async => const Success(unit));
    expect(result.exceptionOrNull(), same(failure));
    expect(await destination.readAsBytes(), [7]);
    expect(await directory.list().toList(), hasLength(1));
  });
  test('refuses inconsistent byte counts and oversized writes even if producer reports success', () async {
    for (final oversized in [false, true]) {
      final result = await const ActionIoFileExport().save(destination.path, (write) async {
        await write(List.filled(oversized ? 65537 : 1, 65));
        return const Success(ActionIoExportSummary(bytes: 0, outputComplete: true, terminal: true));
      }, authorize: () async => const Success(unit));
      expect(result.isError(), isTrue);
      expect(await destination.readAsBytes(), [7]);
      expect(await directory.list().toList(), hasLength(1));
    }
  });
  test('revocation after producing bytes preserves the existing destination', () async {
    var revoked = false;
    final denied = ActionRuntimeFailure.withContext(message: 'Export permission revoked.', code: 'EXPORT_DENIED');
    final result = await const ActionIoFileExport().save(destination.path, (write) async {
      (await write([0, 255])).getOrThrow();
      revoked = true;
      return const Success(ActionIoExportSummary(bytes: 2, outputComplete: true, terminal: true));
    }, authorize: () async => revoked ? Failure(denied) : const Success(unit));
    expect(result.exceptionOrNull(), same(denied));
    expect(await destination.readAsBytes(), [7]);
    expect(await directory.list().toList(), hasLength(1));
  });
}
