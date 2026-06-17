import 'package:plug_agente/domain/repositories/i_global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_directory_acl_normalizer.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

/// Ensures shared global storage directory ACLs are normalized once per app version.
class GlobalStorageAclBootstrap implements IGlobalStorageAclBootstrap {
  GlobalStorageAclBootstrap({
    GlobalStorageDirectoryAclNormalizer? normalizer,
    GlobalStorageAclMarkerStore? markerStore,
  }) : _normalizer = normalizer ?? GlobalStorageDirectoryAclNormalizer(),
       _markerStore = markerStore ?? GlobalStorageAclMarkerStore();

  final GlobalStorageDirectoryAclNormalizer _normalizer;
  final GlobalStorageAclMarkerStore _markerStore;

  IcaclsGrantOutcome? _lastOutcome;
  String? _lastAppDirectoryPath;

  IcaclsGrantOutcome? get lastOutcome => _lastOutcome;

  GlobalStorageAclMarkerSnapshot? markerSnapshot(String appDirectoryPath) {
    return _markerStore.read(appDirectoryPath);
  }

  GlobalStorageAclMarkerStore get markerStore => _markerStore;

  @override
  Future<void> ensureDirectoryAcls(String appDirectoryPath) async {
    _lastAppDirectoryPath = appDirectoryPath;

    if (_markerStore.isFresh(appDirectoryPath)) {
      _lastOutcome = const IcaclsGrantOutcome.success();
      return;
    }

    final outcome = await _normalizer.normalizeDirectory(appDirectoryPath);
    _lastOutcome = outcome;
    if (outcome.isSuccess) {
      await _markerStore.write(
        appDirectoryPath: appDirectoryPath,
        outcome: outcome,
      );
    }
  }

  Future<IcaclsGrantOutcome> normalizeLockFile(String lockFilePath) async {
    return _normalizer.normalizeFile(lockFilePath);
  }

  String? get lastAppDirectoryPath => _lastAppDirectoryPath;
}
