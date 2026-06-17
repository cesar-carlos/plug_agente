/// Ensures shared global storage directory ACLs are normalized for multi-user access.
abstract class IGlobalStorageAclBootstrap {
  Future<void> ensureDirectoryAcls(String appDirectoryPath);
}
