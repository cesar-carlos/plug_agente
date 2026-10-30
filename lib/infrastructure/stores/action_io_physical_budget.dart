import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:result_dart/result_dart.dart';
import 'package:win32/win32.dart' as win32;

/// Admission check only: never deletes evidence or treats free-space failure as
/// permission to write. Call inside the journal's serialized write transaction.
final class ActionIoPhysicalBudget {
  ActionIoPhysicalBudget(
    this.path, {
    Future<int?> Function(String)? freeBytes,
    Future<int> Function()? retainedPayloadBytes,
  }) : _freeBytes = freeBytes ?? _availableBytes,
       _retainedPayloadBytes = retainedPayloadBytes;

  final String path;
  final Future<int?> Function(String) _freeBytes;
  final Future<int> Function()? _retainedPayloadBytes;
  static const int physicalLimit = ActionIoLimits.payloadBytes + ActionIoLimits.storageOverheadBytes;
  static const int terminalReserve = 4 * 1024 * 1024;
  static const int mutationReserve = 1024 * 1024;

  Future<Result<Unit>> checkAdmission(int payloadBytes) => payloadBytes < 0
      ? Future.value(Failure(_failure('ACTION_IO_STORAGE_BUDGET_INVALID')))
      : check(growthBytes: mutationReserve + 2 * payloadBytes, payloadGrowth: payloadBytes);

  Future<Result<Unit>> check({required int growthBytes, int payloadGrowth = 0}) async {
    try {
      if (growthBytes < 0 || payloadGrowth < 0 || payloadGrowth > growthBytes) {
        return Failure(_failure('ACTION_IO_STORAGE_BUDGET_INVALID'));
      }
      var used = 0;
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        final type = FileSystemEntity.typeSync(file.path, followLinks: false);
        if (type == FileSystemEntityType.notFound && suffix.isNotEmpty) continue;
        if (type != FileSystemEntityType.file) return Failure(_failure('ACTION_IO_STORAGE_UNAVAILABLE'));
        used += await file.length();
      }
      final required = growthBytes + terminalReserve;
      if (used + required > physicalLimit) return Failure(_failure('ACTION_IO_STORAGE_QUOTA_EXCEEDED'));
      final retained = await _retainedPayloadBytes?.call() ?? 0;
      if (retained < 0 || retained > ActionIoLimits.payloadBytes) {
        return Failure(_failure('ACTION_IO_STORAGE_BUDGET_INVALID'));
      }
      final overhead = used > retained ? used - retained : 0;
      if (overhead + required - payloadGrowth > ActionIoLimits.storageOverheadBytes) {
        return Failure(_failure('ACTION_IO_STORAGE_QUOTA_EXCEEDED'));
      }
      final available = await _freeBytes(p.dirname(path));
      if (available == null || available < 0) return Failure(_failure('ACTION_IO_STORAGE_SPACE_UNKNOWN'));
      if (available < required) return Failure(_failure('ACTION_IO_STORAGE_SPACE_EXHAUSTED'));
      return const Success(unit);
    } on Object catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  static Future<int?> _availableBytes(String directory) async {
    if (!Platform.isWindows) return null;
    final name = directory.toPcwstr();
    final available = calloc<Uint64>();
    final total = calloc<Uint64>();
    final free = calloc<Uint64>();
    try {
      if (!win32.GetDiskFreeSpaceEx(name, available, total, free).value) return null;
      // Respect the current user's volume quota, including an available value of zero.
      return available.value;
    } finally {
      calloc.free(name);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
  }

  ActionRuntimeFailure _failure(String code, {Object? cause}) => ActionRuntimeFailure.withContext(
    message: 'The I/O journal cannot admit more data. Check its storage budget and available disk space.',
    code: code,
    cause: cause,
  );
}
