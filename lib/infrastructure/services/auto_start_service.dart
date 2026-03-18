import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
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

  static const String _runKeyPath =
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run';
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
          message: 'Falha ao consultar inicializacao automatica global',
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
          message: 'Inicializacao automatica nao suportada neste sistema.',
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
              ? 'Autorizacao UAC cancelada.'
              : _isAccessDenied(result)
              ? 'Permissao negada para habilitar inicializacao global. '
                    'Execute o aplicativo como administrador.'
              : 'Falha ao habilitar inicializacao global',
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
          message: 'Falha ao habilitar inicializacao automatica global',
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
              ? 'Autorizacao UAC cancelada.'
              : _isAccessDenied(result)
              ? 'Permissao negada para desabilitar inicializacao global. '
                    'Execute o aplicativo como administrador.'
              : 'Falha ao desabilitar inicializacao global',
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
          message: 'Falha ao desabilitar inicializacao automatica global',
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
          message: 'Falha ao abrir configuracoes de inicializacao do Windows',
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
    final startProcessLine =
        r'$p = Start-Process -FilePath ' +
        '$psExecutable '
            r'-ArgumentList $arguments -Verb RunAs -Wait -PassThru';

    final script = StringBuffer()
      ..writeln(r'$ErrorActionPreference = "Stop"')
      ..writeln('\$arguments = @($psArgs)')
      ..writeln(startProcessLine)
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
    return output.contains('access is denied') ||
        output.contains('acesso negado');
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
}
