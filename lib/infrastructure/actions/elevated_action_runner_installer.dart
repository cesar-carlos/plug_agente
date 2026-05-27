import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_installer.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_directory_acl_hardener.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_runner_path_resolver.dart';
import 'package:result_dart/result_dart.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Registers and validates the Windows scheduled task for the elevated helper.
class ElevatedActionRunnerInstaller implements IElevatedActionRunnerInstaller {
  ElevatedActionRunnerInstaller({
    required GlobalStorageContext storageContext,
    ProcessRunner? processRunner,
    ElevatedActionDirectoryAclHardener? directoryAclHardener,
    bool Function()? isWindows,
  }) : _storageContext = storageContext,
       _processRunner = processRunner ?? Process.run,
       _directoryAclHardener = directoryAclHardener ?? ElevatedActionDirectoryAclHardener(),
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final GlobalStorageContext _storageContext;
  final ProcessRunner _processRunner;
  final ElevatedActionDirectoryAclHardener _directoryAclHardener;
  final bool Function() _isWindows;

  @override
  Future<ElevatedActionRunnerInstallStatus> getStatus() async {
    if (!_isWindows()) {
      return const ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.unsupportedPlatform,
      );
    }

    final helperPath = ElevatedActionRunnerPathResolver.resolveHelperExecutablePath();
    if (helperPath == null) {
      return const ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.helperExecutableMissing,
      );
    }

    final taskQuery = await _queryScheduledTask();
    if (taskQuery == null) {
      return ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.scheduledTaskMissing,
        helperExecutablePath: helperPath,
      );
    }

    if (!_taskCommandPointsToHelper(taskQuery, helperPath)) {
      // Helper exe moved (post-update) or task was registered with a different
      // path. Force reinstall instead of treating the install as `ready`.
      return ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.helperPathChanged,
        helperExecutablePath: helperPath,
      );
    }

    final markerPresent = File(
      AgentActionElevatedConstants.readyMarkerPath(_storageContext.appDirectoryPath),
    ).existsSync();
    if (!markerPresent) {
      return ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.markerMissing,
        helperExecutablePath: helperPath,
      );
    }

    return ElevatedActionRunnerInstallStatus(
      state: ElevatedActionRunnerInstallState.ready,
      helperExecutablePath: helperPath,
    );
  }

  /// Compares the `Task To Run` field from `schtasks /Query` with the
  /// currently resolved helper path. We normalize case and trim quotes so
  /// the comparison survives quoting differences between Windows shells.
  bool _taskCommandPointsToHelper(String taskQuery, String helperPath) {
    final normalized = helperPath.replaceAll('/', r'\').toLowerCase();
    // Look for any occurrence of the helper path inside the Task To Run
    // line; that line may also contain `--watch-requests <appDir>`.
    for (final line in taskQuery.split(RegExp(r'\r?\n'))) {
      final lower = line.toLowerCase();
      if (!(lower.startsWith('task to run') || lower.startsWith('tarefa a ser executada'))) {
        continue;
      }
      // Strip the field label (`Task To Run: <value>`).
      final colon = line.indexOf(':');
      final value = colon >= 0 ? line.substring(colon + 1) : line;
      return value.replaceAll('"', '').toLowerCase().contains(normalized);
    }
    // If the field is not present (older locale, parsing failed), fall back
    // to a contains-anywhere check as a best-effort guard.
    return taskQuery.toLowerCase().contains(normalized);
  }

  @override
  Future<Result<void>> install({required bool requestElevation}) async {
    if (!_isWindows()) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated action runner install is only supported on Windows.',
          context: {
            'reason': 'unsupported_platform',
            'user_message': 'A preparacao do executor elevado so esta disponivel no Windows.',
          },
        ),
      );
    }

    final helperPath = ElevatedActionRunnerPathResolver.resolveHelperExecutablePath();
    if (helperPath == null) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated helper executable was not found.',
          code: AgentActionFailureCode.elevatedNotConfigured,
          context: {
            'env_key': AgentActionElevatedConstants.helperExecutableEnvKey,
            'default_name': AgentActionElevatedConstants.defaultHelperExecutableName,
            'user_message':
                'O executavel do helper elevado nao foi encontrado. Configure ELEVATED_ACTION_RUNNER_EXE ou instale o helper ao lado do agente.',
          },
        ),
      );
    }

    final taskCommand = _buildScheduledTaskCommand(helperPath: helperPath);
    final createArgs = <String>[
      '/Create',
      '/TN',
      AgentActionElevatedConstants.scheduledTaskName,
      '/TR',
      taskCommand,
      '/SC',
      'ONCE',
      '/ST',
      '00:00',
      '/SD',
      '2000/01/01',
      '/RL',
      'HIGHEST',
      '/F',
    ];

    final createResult = requestElevation
        ? await _runSchtasksWithUacFallback(createArgs)
        : await _runSchtasks(createArgs);
    if (createResult.exitCode != 0) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to register elevated action runner scheduled task.',
          code: AgentActionFailureCode.elevatedSubmitFailed,
          context: {
            'exit_code': createResult.exitCode,
            'stdout': '${createResult.stdout}',
            'stderr': '${createResult.stderr}',
            'user_message': 'Nao foi possivel registrar a tarefa elevada. Confirme o UAC e tente novamente.',
          },
        ),
      );
    }

    await _writeReadyMarker();

    developer.log(
      'Elevated action runner scheduled task registered',
      name: 'elevated_action_runner_installer',
      level: 800,
    );

    return const Success(unit);
  }

  Future<Result<void>> removeScheduledTask({required bool requestElevation}) async {
    if (!_isWindows()) {
      return const Success(unit);
    }

    final deleteArgs = <String>[
      '/Delete',
      '/TN',
      AgentActionElevatedConstants.scheduledTaskName,
      '/F',
    ];
    final deleteResult = requestElevation
        ? await _runSchtasksWithUacFallback(deleteArgs)
        : await _runSchtasks(deleteArgs);
    if (deleteResult.exitCode != 0 && !_isTaskNotFound(deleteResult)) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to remove elevated action runner scheduled task.',
          context: {
            'exit_code': deleteResult.exitCode,
            'user_message': 'Nao foi possivel remover a tarefa elevada.',
          },
        ),
      );
    }

    final marker = File(AgentActionElevatedConstants.readyMarkerPath(_storageContext.appDirectoryPath));
    if (marker.existsSync()) {
      await marker.delete();
    }
    return const Success(unit);
  }

  String _buildScheduledTaskCommand({required String helperPath}) {
    final quotedHelper = '"$helperPath"';
    final quotedAppData = '"${_storageContext.appDirectoryPath}"';
    return '$quotedHelper ${AgentActionElevatedConstants.helperWatchRequestsArgument} $quotedAppData';
  }

  Future<void> _writeReadyMarker() async {
    await _directoryAclHardener.ensureSecured(_storageContext.appDirectoryPath);
    final marker = File(AgentActionElevatedConstants.readyMarkerPath(_storageContext.appDirectoryPath));
    await marker.parent.create(recursive: true);
    await marker.writeAsString('ready\n');
  }

  Future<String?> _queryScheduledTask() async {
    final result = await _runSchtasks(<String>[
      '/Query',
      '/TN',
      AgentActionElevatedConstants.scheduledTaskName,
      '/FO',
      'LIST',
      '/V',
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    return '${result.stdout}';
  }

  Future<ProcessResult> _runSchtasks(List<String> args) {
    return _processRunner('schtasks', args);
  }

  Future<ProcessResult> _runSchtasksWithUacFallback(List<String> args) async {
    final initialResult = await _runSchtasks(args);
    if (initialResult.exitCode == 0 || !_isAccessDenied(initialResult)) {
      return initialResult;
    }

    return _runSchtasksElevated(args);
  }

  Future<ProcessResult> _runSchtasksElevated(List<String> args) {
    final script = _buildElevatedPowerShellScript(
      executable: 'schtasks.exe',
      arguments: args,
    );
    return _processRunner('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
  }

  String _buildElevatedPowerShellScript({
    required String executable,
    required List<String> arguments,
  }) {
    final psExecutable = _quotePowerShellSingle(executable);
    final psArgs = arguments.map(_quotePowerShellSingle).join(', ');
    return '''
\$ErrorActionPreference = "Stop"
\$arguments = @($psArgs)
\$p = Start-Process -FilePath $psExecutable -ArgumentList \$arguments -Verb RunAs -Wait -PassThru
exit \$p.ExitCode
''';
  }

  String _quotePowerShellSingle(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  bool _isAccessDenied(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('access is denied') || output.contains('acesso negado');
  }

  bool _isTaskNotFound(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('cannot find the file specified') ||
        output.contains('nao pode localizar') ||
        output.contains('does not exist');
  }
}
