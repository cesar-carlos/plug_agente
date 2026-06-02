/// Windows ACL grants and marker settings for shared ProgramData storage.
abstract final class GlobalStorageAclConstants {
  static const String markerFileName = '.plug_agente_acl_v1';

  static const Duration icaclsTimeout = Duration(seconds: 10);

  static const int maxLoggedStderrChars = 512;

  /// Authenticated Users — modify with inheritance on directories.
  static const String authenticatedUsersDirectoryGrant = '*S-1-5-11:(OI)(CI)(M)';

  /// Built-in Users — modify with inheritance on directories.
  static const String usersDirectoryGrant = '*S-1-5-32-545:(OI)(CI)(M)';

  /// Authenticated Users — modify on a single file.
  static const String authenticatedUsersFileGrant = '*S-1-5-11:(M)';
}
