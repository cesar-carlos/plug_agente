import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_global_storage_health_snapshot_builder.dart';

final class GlobalStorageHealthSectionBuilder {
  const GlobalStorageHealthSectionBuilder({
    IGlobalStorageHealthSnapshotBuilder? globalStorageHealthSnapshotBuilder,
    GlobalStorageContext? globalStorageContext,
  }) : _globalStorageHealthSnapshotBuilder = globalStorageHealthSnapshotBuilder,
       _globalStorageContext = globalStorageContext;

  final IGlobalStorageHealthSnapshotBuilder? _globalStorageHealthSnapshotBuilder;
  final GlobalStorageContext? _globalStorageContext;

  Map<String, Object?>? build() {
    final builder = _globalStorageHealthSnapshotBuilder;
    final context = _globalStorageContext;
    if (builder == null || context == null) {
      return null;
    }
    return builder.build(context);
  }
}
