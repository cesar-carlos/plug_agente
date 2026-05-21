import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';

typedef IcaclsProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Best-effort Windows ACL restriction for elevated bridge directories.
///
/// Limits inherited access on `agent_actions/elevated/**` to the current user,
/// Administrators and SYSTEM. Failures are logged and do not block execution.
class ElevatedActionDirectoryAclHardener {
  ElevatedActionDirectoryAclHardener({IcaclsProcessRunner? processRunner})
    : _processRunner = processRunner ?? Process.run;

  final IcaclsProcessRunner _processRunner;

  static const String _logName = 'elevated_action_directory_acl';

  Future<ElevatedDirectoryAclOutcome> ensureSecured(String appDirectoryPath) async {
    if (!Platform.isWindows) {
      return ElevatedDirectoryAclOutcome.skippedNonWindows;
    }

    try {
      await _ensureDirectoriesExist(appDirectoryPath);
      final elevatedRoot = p.join(appDirectoryPath, AgentActionElevatedConstants.elevatedSubdirectoryName);
      return _secureDirectory(elevatedRoot);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Unable to prepare elevated directories for ACL hardening',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
      return ElevatedDirectoryAclOutcome.failed;
    }
  }

  Future<void> _ensureDirectoriesExist(String appDirectoryPath) async {
    final directoryPaths = <String>[
      AgentActionElevatedConstants.requestsDirectoryPath(appDirectoryPath),
      AgentActionElevatedConstants.statusDirectoryPath(appDirectoryPath),
      AgentActionElevatedConstants.cancelDirectoryPath(appDirectoryPath),
      AgentActionElevatedConstants.materializedDirectoryPath(appDirectoryPath),
    ];

    for (final directoryPath in directoryPaths) {
      await Directory(directoryPath).create(recursive: true);
    }
  }

  Future<ElevatedDirectoryAclOutcome> _secureDirectory(String directoryPath) async {
    final account = _currentUserAccount();
    if (account == null) {
      return ElevatedDirectoryAclOutcome.skippedNoUser;
    }

    try {
      final result = await _processRunner(
        'icacls',
        <String>[
          directoryPath,
          '/inheritance:r',
          '/grant:r',
          '*S-1-5-18:(OI)(CI)F',
          '*S-1-5-32-544:(OI)(CI)F',
          '$account:(OI)(CI)F',
        ],
      );
      if (result.exitCode == 0) {
        return ElevatedDirectoryAclOutcome.restricted;
      }

      developer.log(
        'icacls returned non-zero exit code for elevated directory',
        name: _logName,
        level: 900,
        error: 'exit_code=${result.exitCode} stderr=${result.stderr}',
      );
      return ElevatedDirectoryAclOutcome.failed;
    } on ProcessException catch (error, stackTrace) {
      developer.log(
        'Failed to start icacls for elevated directory',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
      return ElevatedDirectoryAclOutcome.failed;
    }
  }

  String? _currentUserAccount() {
    final username = Platform.environment['USERNAME']?.trim() ?? '';
    final userDomain = Platform.environment['USERDOMAIN']?.trim() ?? '';
    if (username.isEmpty) {
      return null;
    }
    return userDomain.isEmpty ? username : '$userDomain\\$username';
  }
}

enum ElevatedDirectoryAclOutcome {
  restricted,
  skippedNonWindows,
  skippedNoUser,
  failed,
}
