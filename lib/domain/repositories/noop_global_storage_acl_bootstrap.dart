import 'package:plug_agente/domain/repositories/i_global_storage_acl_bootstrap.dart';

/// No-op ACL bootstrap for non-Windows paths and tests that do not exercise ACL wiring.
class NoopGlobalStorageAclBootstrap implements IGlobalStorageAclBootstrap {
  const NoopGlobalStorageAclBootstrap();

  @override
  Future<void> ensureDirectoryAcls(String appDirectoryPath) async {}
}
