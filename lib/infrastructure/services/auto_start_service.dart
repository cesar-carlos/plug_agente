import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
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

typedef WindowsPlatformResolver = bool Function();

typedef ExecutablePathProvider = String Function();

class AutoStartService implements IStartupService {
  AutoStartService({
    ProcessRunner? processRunner,
    DetachedProcessStarter? processStarter,
    WindowsPlatformResolver? isWindows,
    ExecutablePathProvider? executablePathProvider,
  }) : _processRunner = processRunner ?? Process.run,
       _processStarter = processStarter ?? _defaultProcessStarter,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _executablePathProvider = executablePathProvider ?? (() => Platform.resolvedExecutable);

  static const String _runValueName = 'Plug Agente';

  final ProcessRunner _processRunner;
  final DetachedProcessStarter _processStarter;
  final WindowsPlatformResolver _isWindows;
  final ExecutablePathProvider _executablePathProvider;

  @override
  Future<Result<bool>> isEnabled() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final enabled = queryResults.any((result) => result.exists);

      developer.log(
        'Auto-start status: $enabled',
        name: 'startup_service',
        level: 800,
      );

      return Success(enabled);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to query auto-start status',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to query auto-start status',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
  }) async {
    if (!_isWindows()) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final existingEntries = queryResults.where((result) => result.exists).toList();
      if (existingEntries.isEmpty) {
        return const Success(StartupLaunchConfigurationStatus.unchanged);
      }

      if (!_needsRepair(existingEntries)) {
        return const Success(StartupLaunchConfigurationStatus.unchanged);
      }

      if (!allowElevation) {
        developer.log(
          'Auto-start entry needs repair, but elevation is disabled for this validation pass.',
          name: 'startup_service',
          level: 800,
        );
        return const Success(StartupLaunchConfigurationStatus.needsRepair);
      }
      developer.log(
        'Auto-start entry is stale, duplicated, or missing launch arguments. Repairing.',
        name: 'startup_service',
        level: 800,
      );
      final repairResult = await _repairStartupEntries(existingEntries);
      return repairResult.fold(
        (_) => const Success(StartupLaunchConfigurationStatus.repaired),
        Failure.new,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to validate auto-start launch configuration',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to validate auto-start launch configuration',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> enable() async {
    if (!_isWindows()) {
      return const Failure(
        StartupServiceFailure(
          message: 'Auto-start is not supported on this platform.',
        ),
      );
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final expectedExecutable = _executablePathProvider();
      final hasHealthyEntry = queryResults.any(
        (result) => result.entry?.isHealthyFor(expectedExecutable) ?? false,
      );
      if (hasHealthyEntry) {
        developer.log(
          'Auto-start already has a healthy registry entry',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      return _writeStartupEntry(StartupRegistryScope.currentUser);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to enable auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to enable auto-start',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> disable() async {
    if (!_isWindows()) {
      return const Success(unit);
    }

    try {
      for (final scope in StartupRegistryScope.values) {
        final deleteResult = await _deleteStartupEntry(scope);
        if (deleteResult.isError()) {
          return deleteResult;
        }
      }

      developer.log(
        'Auto-start disabled successfully',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to disable auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to disable auto-start',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<Unit>> openSystemSettings() async {
    if (!_isWindows()) {
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

  Future<List<_StartupRegistryQueryResult>> _queryStartupRegistry() async {
    final results = <_StartupRegistryQueryResult>[];
    for (final scope in StartupRegistryScope.values) {
      final result = await _runRegCommand(<String>[
        'query',
        scope.runKeyPath,
        '/v',
        _runValueName,
      ]);
      final output = '${result.stdout}\n${result.stderr}';
      results.add(
        _StartupRegistryQueryResult(
          scope: scope,
          result: result,
          entry: result.exitCode == 0
              ? StartupRegistryEntry.tryParse(
                  scope: scope,
                  valueName: _runValueName,
                  output: output,
                )
              : null,
        ),
      );
    }
    return results;
  }

  bool _needsRepair(List<_StartupRegistryQueryResult> existingEntries) {
    final expectedExecutable = _executablePathProvider();
    final healthyEntries = existingEntries
        .where(
          (result) => result.entry?.isHealthyFor(expectedExecutable) ?? false,
        )
        .toList();
    return existingEntries.length != 1 || healthyEntries.length != 1;
  }

  Future<Result<Unit>> _repairStartupEntries(
    List<_StartupRegistryQueryResult> existingEntries,
  ) async {
    final expectedExecutable = _executablePathProvider();
    final hasHealthyCurrentUserEntry = existingEntries.any(
      (result) =>
          result.scope == StartupRegistryScope.currentUser && (result.entry?.isHealthyFor(expectedExecutable) ?? false),
    );

    if (!hasHealthyCurrentUserEntry) {
      final writeResult = await _writeStartupEntry(StartupRegistryScope.currentUser);
      if (writeResult.isError()) {
        return writeResult;
      }
    }

    if (existingEntries.any((result) => result.scope == StartupRegistryScope.localMachine)) {
      final deleteResult = await _deleteStartupEntry(StartupRegistryScope.localMachine);
      if (deleteResult.isError()) {
        return deleteResult;
      }
    }

    return const Success(unit);
  }

  Future<Result<Unit>> _writeStartupEntry(StartupRegistryScope scope) async {
    final valueData =
        '"${_executablePathProvider()}" '
        '"${AppStrings.singleInstanceArgAutostart}"';

    final result = await _runRegCommandWithUacFallback(
      <String>[
        'add',
        scope.runKeyPath,
        '/v',
        _runValueName,
        '/t',
        'REG_SZ',
        '/d',
        valueData,
        '/f',
      ],
      allowElevation: scope.requiresElevation,
    );

    if (result.exitCode == 0) {
      developer.log(
        'Auto-start enabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(
      StartupServiceFailure(
        message: _failureMessage(
          result: result,
          action: 'enabling auto-start',
          scope: scope,
        ),
      ),
    );
  }

  Future<Result<Unit>> _deleteStartupEntry(StartupRegistryScope scope) async {
    final result = await _runRegCommandWithUacFallback(
      <String>[
        'delete',
        scope.runKeyPath,
        '/v',
        _runValueName,
        '/f',
      ],
      allowElevation: scope.requiresElevation,
    );

    if (result.exitCode == 0 || _isValueNotFound(result)) {
      developer.log(
        'Auto-start disabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(
      StartupServiceFailure(
        message: _failureMessage(
          result: result,
          action: 'disabling auto-start',
          scope: scope,
        ),
      ),
    );
  }

  Future<ProcessResult> _runRegCommandWithUacFallback(
    List<String> args, {
    required bool allowElevation,
  }) async {
    final initialResult = await _runRegCommand(args);
    if (initialResult.exitCode == 0 || !allowElevation || !_isAccessDenied(initialResult)) {
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

  String _failureMessage({
    required ProcessResult result,
    required String action,
    required StartupRegistryScope scope,
  }) {
    if (_isUacCancelled(result)) {
      return 'UAC authorization cancelled.';
    }
    if (_isAccessDenied(result)) {
      return 'Permission denied when $action in ${scope.label}.';
    }
    return 'Failed when $action in ${scope.label}.';
  }

  bool _isAccessDenied(ProcessResult result) {
    final output = _normalizedProcessOutput(result);
    return output.contains('access is denied') || output.contains('acesso negado');
  }

  bool _isUacCancelled(ProcessResult result) {
    final output = _normalizedProcessOutput(result);
    return output.contains('operation was canceled by the user') ||
        output.contains('operation was cancelled by the user') ||
        output.contains('operacao foi cancelada pelo usuario') ||
        output.contains('a operacao foi cancelada pelo usuario');
  }

  bool _isValueNotFound(ProcessResult result) {
    final output = _normalizedProcessOutput(result);
    return output.contains(
          'unable to find the specified registry key or value',
        ) ||
        output.contains('nao e possivel localizar a chave ou valor') ||
        output.contains('o sistema nao pode encontrar a chave') ||
        output.contains('o sistema nao pode encontrar o valor');
  }

  String _normalizedProcessOutput(ProcessResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return _stripDiacritics(output);
  }
}

String _stripDiacritics(String value) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    buffer.write(replacements[character] ?? character);
  }
  return buffer.toString();
}

class _StartupRegistryQueryResult {
  const _StartupRegistryQueryResult({
    required this.scope,
    required this.result,
    required this.entry,
  });

  final StartupRegistryScope scope;
  final ProcessResult result;
  final StartupRegistryEntry? entry;

  bool get exists => result.exitCode == 0;
}
