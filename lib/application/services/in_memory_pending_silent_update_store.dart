import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/repositories/i_pending_silent_update_store.dart';
import 'package:result_dart/result_dart.dart';

/// In-memory implementation used by tests and fallback when no settings
/// store is wired. Keeps the coordinator independent of the persistence
/// strategy in unit tests.
class InMemoryPendingSilentUpdateStore implements IPendingSilentUpdateStore {
  PendingSilentUpdate? _pending;

  @override
  Future<Result<PendingSilentUpdateSnapshot>> load() async => Success(PendingSilentUpdateSnapshot(_pending));

  @override
  Future<Result<void>> save(PendingSilentUpdate pending) async {
    _pending = pending;
    return const Success(unit);
  }

  @override
  Future<Result<void>> remove() async {
    _pending = null;
    return const Success(unit);
  }
}

/// No-op reader that always returns `null`. Tests / non-Windows runs
/// can inject it so the coordinator stays free of `dart:io` when the
/// helper status file is irrelevant.
class NoopSilentUpdateLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  const NoopSilentUpdateLauncherStatusReader();

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async => null;

  @override
  Future<bool> fileExists(String? path) async => false;
}
