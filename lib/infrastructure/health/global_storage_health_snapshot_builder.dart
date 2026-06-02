import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_global_storage_health_snapshot_builder.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';

class GlobalStorageHealthSnapshotBuilder implements IGlobalStorageHealthSnapshotBuilder {
  GlobalStorageHealthSnapshotBuilder({
    required GlobalStorageAclBootstrap aclBootstrap,
    required GlobalStorageAclMarkerStore markerStore,
  }) : _aclBootstrap = aclBootstrap,
       _markerStore = markerStore;

  final GlobalStorageAclBootstrap _aclBootstrap;
  final GlobalStorageAclMarkerStore _markerStore;

  @override
  Map<String, Object?> build(GlobalStorageContext context) {
    final marker = _markerStore.read(context.appDirectoryPath);
    final lastOutcome = _aclBootstrap.lastOutcome;

    return <String, Object?>{
      'app_directory_path': context.appDirectoryPath,
      'acl_marker_present': marker != null,
      if (marker?.normalizedAt != null) 'acl_normalized_at': marker!.normalizedAt!.toUtc().toIso8601String(),
      if (marker?.lastOutcome != null) 'acl_marker_outcome': marker!.lastOutcome,
      if (lastOutcome != null) 'acl_last_outcome': lastOutcome.diagnosticName,
    };
  }
}
