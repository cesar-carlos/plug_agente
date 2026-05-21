import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_directory_acl_hardener.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_runner_path_resolver.dart';
import 'package:result_dart/result_dart.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Registers and validates the Windows scheduled task for the elevated helper.
class ElevatedActionRunnerInstaller {
  ElevatedActionRunnerInstaller({
    required GlobalStorageContext storageContext,
    ProcessRunner? processRunner,
    ElevatedActionDirectoryAclHardener? directoryAclHardener,
  }) : _storageContext = storageContext,
       _processRunner = processRunner ?? Process.run,
       _directoryAclHardener = directoryAclHardener ?? ElevatedActionDirectoryAclHardener();

  final GlobalStorageContext _storageContext;
  final ProcessRunner _processRunner;
  final ElevatedActionDirectoryAclHardener _directoryAclHardener;

  Future<ElevatedActionRunnerInstallStatus> getStatus() async {
    if (!Platform.isWindows) {
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

    final taskRegistered = await _isScheduledTaskRegistered();
    final markerPresent = File(AgentActionElevatedConstants.readyMarkerPath(_storageContext.appDirectoryPath)).existsSync();
    if (!taskRegistered) {
      return ElevatedActionRunnerInstallStatus(
        state: ElevatedActionRunnerInstallState.scheduledTaskMissing,
        helperExecutablePath: helperPath,
      );
    }
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

  Future<Result<void>> install({required bool requestElevation}) async {
    if (!Platform.isWindows) {
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
            'user_message':
                'Nao foi possivel registrar a tarefa elevada. Confirme o UAC e tente novamente.',
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
    if (!Platform.isWindows) {
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

  Future<bool> _isScheduledTaskRegistered() async {
    final result = await _runSchtasks(<String>[
      '/Query',
      '/TN',
      AgentActionElevatedConstants.scheduledTaskName,
      '/FO',
      'LIST',
      '/V',
    ]);
    return result.exitCode == 0;
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
