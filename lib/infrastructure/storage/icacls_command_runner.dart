import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/global_storage_acl_constants.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

typedef IcaclsProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Runs icacls with timeout and combined /grant arguments.
class IcaclsCommandRunner {
  IcaclsCommandRunner({
    IcaclsProcessRunner? processRunner,
    Duration? timeout,
  }) : _processRunner = processRunner ?? Process.run,
       _timeout = timeout ?? GlobalStorageAclConstants.icaclsTimeout;

  static const String _logName = 'icacls_command_runner';

  final IcaclsProcessRunner _processRunner;
  final Duration _timeout;

  Future<IcaclsGrantOutcome> grant({
    required String targetPath,
    required List<String> grantEntries,
    required String operation,
  }) async {
    if (!Platform.isWindows) {
      return const IcaclsGrantOutcome.skippedNonWindows();
    }

    if (grantEntries.isEmpty) {
      return const IcaclsGrantOutcome.success();
    }

    final arguments = <String>[
      targetPath,
      for (final grant in grantEntries) ...<String>['/grant', grant],
    ];

    try {
      final result = await _processRunner('icacls', arguments).timeout(_timeout);
      if (result.exitCode == 0) {
        return const IcaclsGrantOutcome.success();
      }

      final stderr = _truncateStderr(result.stderr);
      developer.log(
        'icacls returned non-zero exit code',
        name: _logName,
        level: 900,
        error: 'operation=$operation path=$targetPath exit_code=${result.exitCode} stderr=$stderr',
      );
      return IcaclsGrantOutcome.nonZeroExit(
        exitCode: result.exitCode,
        stderr: stderr,
      );
    } on TimeoutException {
      developer.log(
        'icacls timed out',
        name: _logName,
        level: 900,
        error: 'operation=$operation path=$targetPath timeout_ms=${_timeout.inMilliseconds}',
      );
      return const IcaclsGrantOutcome.timeout();
    } on ProcessException catch (error, stackTrace) {
      developer.log(
        'Failed to start icacls',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
      return IcaclsGrantOutcome.processFailed(stderr: error.message);
    }
  }

  String? _truncateStderr(dynamic stderr) {
    final text = '${stderr ?? ''}'.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.length <= GlobalStorageAclConstants.maxLoggedStderrChars) {
      return text;
    }
    return '${text.substring(0, GlobalStorageAclConstants.maxLoggedStderrChars)}...';
  }
}
