import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/utils/launch_args.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:result_dart/result_dart.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

typedef DetachedProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });

class AutoStartService implements IStartupService {
  AutoStartService({
    ProcessRunner? processRunner,
    DetachedProcessStarter? processStarter,
  }) : _processRunner = processRunner ?? Process.run,
       _processStarter = processStarter ?? _defaultProcessStarter;

  static const String _runKeyPath = r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _runValueName = 'Plug Agente';

  final ProcessRunner _processRunner;
  final DetachedProcessStarter _processStarter;

  @override
  Future<Result<bool>> isEnabled() async {
    if (!Platform.isWindows) {
      return const Success(false);
    }

    try {
      final result = await _runRegCommand(<String>[
        'query',
        _runKeyPath,
        '/v',
        _runValueName,
      ]);
      final enabled = result.exitCode == 0;

      developer.log(
        'Global auto-start status: $enabled',
        name: 'startup_service',
        level: 800,
      );

      return Success(enabled);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to query global auto-start status',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to query global auto-start status',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
  }) async {
    if (!Platform.isWindows) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    try {
      final result = await _runRegCommand(<String>[
        'query',
        _runKeyPath,
        '/v',
        _runValueName,
      ]);

      if (result.exitCode != 0) {
        return const Success(StartupLaunchConfigurationStatus.unchanged);
      }

      if (_hasAutostartArgument(result)) {
        return const Success(StartupLaunchConfigurationStatus.unchanged);
      }

      if (!allowElevation) {
        developer.log(
          'Global auto-start entry needs repair, but elevation is disabled for this validation pass.',
          name: 'startup_service',
          level: 800,
        );
        return const Success(StartupLaunchConfigurationStatus.needsRepair);
      }
      developer.log(
        'Global auto-start entry is missing launch arguments. Repairing.',
        name: 'startup_service',
        level: 800,
      );
      final repairResult = await enable();
      return repairResult.fold(
        (_) => const Success(StartupLaunchConfigurationStatus.repaired),
        Failure.new,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to validate global auto-start launch configuration',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to validate global auto-start launch configuration',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> enable() async {
    if (!Platform.isWindows) {
      return const Failure(
        StartupServiceFailure(
          message: 'Auto-start is not supported on this platform.',
        ),
      );
    }

    try {
      final valueData =
          '"${Platform.resolvedExecutable}" '
          '"${AppStrings.singleInstanceArgAutostart}"';

      final result = await _runRegCommandWithUacFallback(<String>[
        'add',
        _runKeyPath,
        '/v',
        _runValueName,
        '/t',
        'REG_SZ',
        '/d',
        valueData,
        '/f',
      ]);

      if (result.exitCode == 0) {
        developer.log(
          'Global auto-start enabled successfully (HKLM)',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      return Failure(
        StartupServiceFailure(
          message: _isUacCancelled(result)
              ? 'UAC authorization cancelled.'
              : _isAccessDenied(result)
              ? 'Permission denied when enabling global auto-start. '
                    'Run the application as administrator.'
              : 'Failed to enable global auto-start',
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to enable global auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to enable global auto-start',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> disable() async {
    if (!Platform.isWindows) {
      return const Success(unit);
    }

    try {
      final result = await _runRegCommandWithUacFallback(<String>[
        'delete',
        _runKeyPath,
        '/v',
        _runValueName,
        '/f',
      ]);

      if (result.exitCode == 0 || _isValueNotFound(result)) {
        developer.log(
          'Global auto-start disabled successfully (HKLM)',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      return Failure(
        StartupServiceFailure(
          message: _isUacCancelled(result)
              ? 'UAC authorization cancelled.'
              : _isAccessDenied(result)
              ? 'Permission denied when disabling global auto-start. '
                    'Run the application as administrator.'
              : 'Failed to disable global auto-start',
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to disable global auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to disable global auto-start',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> openSystemSettings() async {
    if (!Platform.isWindows) {
      return const Success(unit);
    }

    try {
      await _processStarter(
        'cmd',
        const <String>['/c', 'start', '', 'ms-settings:startupapps'],
        mode: ProcessStartMode.detached,
      );

      developer.log(
        'Opened Windows startup settings',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to open startup settings',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to open Windows startup settings',
          cause: error,
        ),
      );
    }
  }

  Future<ProcessResult> _runRegCommandWithUacFallback(
    List<String> args,
  ) async {
    final initialResult = await _runRegCommand(args);
    if (initialResult.exitCode == 0 || !_isAccessDenied(initialResult)) {
      return initialResult;
    }

    developer.log(
      'Admin privileges required. Requesting UAC elevation.',
      name: 'startup_service',
      level: 800,
    );

    return _runRegCommandElevated(args);
  }

  Future<ProcessResult> _runRegCommand(List<String> args) {
    return _processRunner('reg', args);
  }

  Future<ProcessResult> _runRegCommandElevated(List<String> args) {
    final script = _buildElevatedPowerShellScript(
      executable: 'reg.exe',
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
    final startProcessLine = StringBuffer(r'$p = Start-Process -FilePath ')
      ..write(psExecutable)
      ..write(r' -ArgumentList $arguments -Verb RunAs -Wait -PassThru');

    final script = StringBuffer()
      ..writeln(r'$ErrorActionPreference = "Stop"')
      ..writeln('\$arguments = @($psArgs)')
      ..writeln(startProcessLine.toString())
      ..writeln(r'exit $p.ExitCode');

    return script.toString();
  }

  String _quotePowerShellSingle(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(executable, arguments, mode: mode);
  }

  bool _isAccessDenied(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('access is denied') || output.contains('acesso negado');
  }

  bool _isUacCancelled(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('operation was canceled by the user') ||
        output.contains('operation was cancelled by the user') ||
        output.contains('operacao foi cancelada pelo usuario') ||
        output.contains('a operacao foi cancelada pelo usuario');
  }

  bool _isValueNotFound(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains(
          'unable to find the specified registry key or value',
        ) ||
        output.contains('nao e possivel localizar a chave ou valor');
  }

  bool _hasAutostartArgument(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}';
    return containsAutostartLaunchToken(output);
  }
}
