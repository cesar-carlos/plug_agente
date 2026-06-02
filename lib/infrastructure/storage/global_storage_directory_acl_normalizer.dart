import 'dart:io';

import 'package:plug_agente/core/constants/global_storage_acl_constants.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

/// Best-effort Windows ACL grants so shared ProgramData data works for standard users.
class GlobalStorageDirectoryAclNormalizer {
  GlobalStorageDirectoryAclNormalizer({
    IcaclsCommandRunner? commandRunner,
  }) : _commandRunner = commandRunner ?? IcaclsCommandRunner();

  final IcaclsCommandRunner _commandRunner;

  Future<IcaclsGrantOutcome> normalizeDirectory(String directoryPath) async {
    if (!Platform.isWindows) {
      return const IcaclsGrantOutcome.skippedNonWindows();
    }

    return _commandRunner.grant(
      targetPath: directoryPath,
      grantEntries: <String>[
        GlobalStorageAclConstants.authenticatedUsersDirectoryGrant,
        GlobalStorageAclConstants.usersDirectoryGrant,
      ],
      operation: 'normalize_directory',
    );
  }

  Future<IcaclsGrantOutcome> normalizeFile(String filePath) async {
    if (!Platform.isWindows) {
      return const IcaclsGrantOutcome.skippedNonWindows();
    }

    return _commandRunner.grant(
      targetPath: filePath,
      grantEntries: <String>[GlobalStorageAclConstants.authenticatedUsersFileGrant],
      operation: 'normalize_file',
    );
  }
}
