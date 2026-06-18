import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_elevated_registry_executor.dart';
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
    WindowsElevatedRegistryExecutor? elevatedRegistryExecutor,
  }) : _processRunner = processRunner ?? Process.run,
       _processStarter = processStarter ?? _defaultProcessStarter,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _executablePathProvider = executablePathProvider ?? (() => Platform.resolvedExecutable),
       _elevatedRegistryExecutor =
           elevatedRegistryExecutor ?? WindowsElevatedRegistryExecutor(processRunner: processRunner);

  static const String runValueName = 'Plug Agente';

  final ProcessRunner _processRunner;
  final DetachedProcessStarter _processStarter;
  final WindowsPlatformResolver _isWindows;
  final ExecutablePathProvider _executablePathProvider;
  final WindowsElevatedRegistryExecutor _elevatedRegistryExecutor;

  @override
  Future<Result<bool>> isEnabled() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final expectedExecutable = _executablePathProvider();
      final enabled = queryResults.any(
        (result) => result.entry?.isHealthyFor(expectedExecutable) ?? false,
      );

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
      return _evaluateLaunchConfiguration(allowElevation: allowElevation);
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

  Future<Result<StartupLaunchConfigurationStatus>> _evaluateLaunchConfiguration({
    required bool allowElevation,
  }) async {
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
      Success.new,
      Failure.new,
    );
  }

  @override
  Future<Result<Unit>> enable() async {
    if (!_isWindows()) {
      return const Failure(
        StartupServiceFailure(
          message: 'Auto-start is not supported on this platform.',
          code: StartupServiceFailureCode.unsupportedPlatform,
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
      final queryResults = await _queryStartupRegistry();
      final existingScopes = queryResults.where((result) => result.exists).map((result) => result.scope);

      for (final scope in existingScopes) {
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

  @override
  Future<Result<bool>> hasRegistryEntryMissingAutostartForCurrentExecutable() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final expectedExecutable = _executablePathProvider();
      final hasUnhealthyEntry = queryResults.any((result) {
        if (!result.exists) {
          return false;
        }
        final entry = result.entry;
        if (entry == null) {
          return false;
        }
        return entry.matchesExpectedExecutable(expectedExecutable) && !entry.hasAutostartArgument;
      });
      return Success(hasUnhealthyEntry);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to inspect startup registry entry health',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to inspect startup registry entry health',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<String>> buildStartupDiagnosticReport() async {
    if (!_isWindows()) {
      return const Failure(
        StartupServiceFailure(
          message: 'Startup diagnostics are only available on Windows.',
          code: StartupServiceFailureCode.unsupportedPlatform,
        ),
      );
    }

    try {
      final expectedExecutable = _executablePathProvider();
      final queryResults = await _queryStartupRegistry();
      final buffer = StringBuffer('Plug Agente startup diagnostic\n')
        ..writeln('Expected executable: $expectedExecutable')
        ..writeln('Expected autostart arg: ${LaunchArgsConstants.autostartArg}')
        ..writeln();

      for (final result in queryResults) {
        buffer
          ..writeln('Scope: ${result.scope.label}')
          ..writeln('  Exists: ${result.exists}');
        final entry = result.entry;
        if (entry != null) {
          buffer
            ..writeln('  Executable: ${entry.executablePath}')
            ..writeln('  Has autostart arg: ${entry.hasAutostartArgument}')
            ..writeln('  Healthy for current exe: ${entry.isHealthyFor(expectedExecutable)}')
            ..writeln('  Raw value: ${entry.rawValue}');
        }
        buffer.writeln();
      }

      final existing = queryResults.where((result) => result.exists).toList();
      buffer.writeln('Needs repair: ${_needsRepair(existing)}');

      return Success(buffer.toString().trimRight());
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to build startup diagnostic report',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        StartupServiceFailure(
          message: 'Failed to build startup diagnostic report',
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
        runValueName,
      ]);
      final output = '${result.stdout}\n${result.stderr}';
      results.add(
        _StartupRegistryQueryResult(
          scope: scope,
          result: result,
          entry: result.exitCode == 0
              ? StartupRegistryEntry.tryParse(
                  scope: scope,
                  valueName: runValueName,
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

  bool _hasHealthyCurrentUserEntry(List<_StartupRegistryQueryResult> entries) {
    final expectedExecutable = _executablePathProvider();
    return entries.any(
      (result) =>
          result.scope == StartupRegistryScope.currentUser && (result.entry?.isHealthyFor(expectedExecutable) ?? false),
    );
  }

  Future<Result<StartupLaunchConfigurationStatus>> _repairStartupEntries(
    List<_StartupRegistryQueryResult> existingEntries,
  ) async {
    final hasHealthyCurrentUserEntry = _hasHealthyCurrentUserEntry(existingEntries);

    if (!hasHealthyCurrentUserEntry) {
      final writeResult = await _writeStartupEntry(StartupRegistryScope.currentUser);
      if (writeResult.isError()) {
        return Failure(writeResult.exceptionOrNull()! as StartupServiceFailure);
      }
    }

    var legacyMachineEntryRemains = false;
    for (final scope in StartupRegistryScope.machineScopes) {
      final hasMachineEntry = existingEntries.any((result) => result.scope == scope);
      if (!hasMachineEntry) {
        continue;
      }

      final deleteResult = await _deleteStartupEntry(scope);
      if (deleteResult.isError()) {
        if (_hasHealthyCurrentUserEntry(existingEntries) || await _hasHealthyCurrentUserEntryAfterQuery()) {
          legacyMachineEntryRemains = true;
          developer.log(
            'Could not remove legacy machine startup entry (${scope.label}); HKCU entry is healthy.',
            name: 'startup_service',
            level: 800,
          );
          continue;
        }
        return Failure(deleteResult.exceptionOrNull()! as StartupServiceFailure);
      }
    }

    final postRepairStatus = await _resolveStatusAfterRepair(legacyMachineEntryRemains: legacyMachineEntryRemains);
    return Success(postRepairStatus);
  }

  Future<bool> _hasHealthyCurrentUserEntryAfterQuery() async {
    final queryResults = await _queryStartupRegistry();
    final existingEntries = queryResults.where((result) => result.exists).toList();
    return _hasHealthyCurrentUserEntry(existingEntries);
  }

  Future<StartupLaunchConfigurationStatus> _resolveStatusAfterRepair({
    required bool legacyMachineEntryRemains,
  }) async {
    final validation = await _evaluateLaunchConfiguration(allowElevation: false);
    return validation.fold(
      (status) {
        if (status == StartupLaunchConfigurationStatus.needsRepair) {
          if (legacyMachineEntryRemains) {
            return StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry;
          }
          return StartupLaunchConfigurationStatus.needsRepair;
        }
        if (legacyMachineEntryRemains && status == StartupLaunchConfigurationStatus.unchanged) {
          return StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry;
        }
        if (status == StartupLaunchConfigurationStatus.unchanged) {
          return StartupLaunchConfigurationStatus.repaired;
        }
        return status;
      },
      (_) {
        if (legacyMachineEntryRemains) {
          return StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry;
        }
        return StartupLaunchConfigurationStatus.repaired;
      },
    );
  }

  Future<Result<Unit>> _writeStartupEntry(StartupRegistryScope scope) async {
    final valueData =
        '"${_executablePathProvider()}" '
        '"${LaunchArgsConstants.autostartArg}"';

    if (scope.requiresElevation) {
      final result = await _elevatedRegistryExecutor.setRunValue(
        scope: scope,
        valueName: runValueName,
        rawValueData: valueData,
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
        _failureFromProcessResult(
          result: result,
          action: 'enabling auto-start',
          scope: scope,
          isWrite: true,
        ),
      );
    }

    final result = await _runRegCommand(<String>[
      'add',
      scope.runKeyPath,
      '/v',
      runValueName,
      '/t',
      'REG_SZ',
      '/d',
      valueData,
      '/f',
    ]);

    if (result.exitCode == 0) {
      developer.log(
        'Auto-start enabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(
      _failureFromProcessResult(
        result: result,
        action: 'enabling auto-start',
        scope: scope,
        isWrite: true,
      ),
    );
  }

  Future<Result<Unit>> _deleteStartupEntry(StartupRegistryScope scope) async {
    if (scope.requiresElevation) {
      final initialResult = await _runRegCommand(<String>[
        'delete',
        scope.runKeyPath,
        '/v',
        runValueName,
        '/f',
      ]);

      if (initialResult.exitCode == 0 || _isValueNotFound(initialResult)) {
        developer.log(
          'Auto-start disabled successfully (${scope.label})',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      if (!_isAccessDenied(initialResult)) {
        return Failure(_failureFromProcessResult(result: initialResult, action: 'disabling auto-start', scope: scope));
      }

      developer.log(
        'Admin privileges required. Requesting UAC elevation (${scope.label}).',
        name: 'startup_service',
        level: 800,
      );

      final elevatedResult = await _elevatedRegistryExecutor.deleteRunValue(
        scope: scope,
        valueName: runValueName,
      );

      if (elevatedResult.exitCode == 0) {
        developer.log(
          'Auto-start disabled successfully (${scope.label})',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      return Failure(_failureFromProcessResult(result: elevatedResult, action: 'disabling auto-start', scope: scope));
    }

    final result = await _runRegCommand(<String>[
      'delete',
      scope.runKeyPath,
      '/v',
      runValueName,
      '/f',
    ]);

    if (result.exitCode == 0 || _isValueNotFound(result)) {
      developer.log(
        'Auto-start disabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(_failureFromProcessResult(result: result, action: 'disabling auto-start', scope: scope));
  }

  Future<ProcessResult> _runRegCommand(List<String> args) {
    return _processRunner('reg', args);
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(executable, arguments, mode: mode);
  }

  StartupServiceFailure _failureFromProcessResult({
    required ProcessResult result,
    required String action,
    required StartupRegistryScope scope,
    bool isWrite = false,
  }) {
    final message = _failureMessage(result: result, action: action, scope: scope);
    final code = _failureCode(result, isWrite: isWrite);
    developer.log(
      message,
      name: 'startup_service',
      level: 900,
    );
    return StartupServiceFailure(
      message: message,
      code: code,
      registryScopeLabel: scope.label,
    );
  }

  StartupServiceFailureCode _failureCode(ProcessResult result, {required bool isWrite}) {
    if (_isUacCancelled(result)) {
      return StartupServiceFailureCode.uacCancelled;
    }
    if (_isAccessDenied(result)) {
      return StartupServiceFailureCode.accessDenied;
    }
    return isWrite ? StartupServiceFailureCode.registryWriteFailed : StartupServiceFailureCode.registryDeleteFailed;
  }

  String _failureMessage({
    required ProcessResult result,
    required String action,
    required StartupRegistryScope scope,
  }) {
    if (_isUacCancelled(result)) {
      return 'UAC authorization cancelled when $action in ${scope.label}.';
    }
    if (_isAccessDenied(result)) {
      return 'Permission denied when $action in ${scope.label}.';
    }
    return 'Failed when $action in ${scope.label}.';
  }

  bool _isAccessDenied(ProcessResult result) => WindowsElevatedRegistryExecutor.isAccessDenied(result);

  bool _isUacCancelled(ProcessResult result) => WindowsElevatedRegistryExecutor.isUacCancelled(result);

  bool _isValueNotFound(ProcessResult result) {
    final output = WindowsElevatedRegistryExecutor.normalizedProcessOutput(result);
    return output.contains(
          'unable to find the specified registry key or value',
        ) ||
        output.contains('nao e possivel localizar a chave ou valor') ||
        output.contains('o sistema nao pode encontrar a chave') ||
        output.contains('o sistema nao pode encontrar o valor');
  }
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
