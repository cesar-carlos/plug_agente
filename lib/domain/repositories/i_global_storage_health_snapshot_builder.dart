import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

/// Builds the `global_storage` block for agent health responses.
abstract interface class IGlobalStorageHealthSnapshotBuilder {
  Map<String, Object?> build(GlobalStorageContext context);
}
