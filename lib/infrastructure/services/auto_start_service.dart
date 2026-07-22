import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_elevated_registry_executor.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_writer.dart';
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
    IStartupRunValueRegistryReader? registryReader,
    IStartupRunValueRegistryWriter? registryWriter,
  }) : _processRunner = processRunner ?? Process.run,
       _processStarter = processStarter ?? _defaultProcessStarter,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _executablePathProvider = executablePathProvider ?? (() => Platform.resolvedExecutable),
       _elevatedRegistryExecutor =
           elevatedRegistryExecutor ?? WindowsElevatedRegistryExecutor(processRunner: processRunner),
       _registryReader = registryReader ?? const Win32StartupRunValueRegistryReader(),
       _registryWriter = registryWriter ?? const Win32StartupRunValueRegistryWriter();

  static const String runValueName = 'Plug Agente';

  final ProcessRunner _processRunner;
  final DetachedProcessStarter _processStarter;
  final WindowsPlatformResolver _isWindows;
  final ExecutablePathProvider _executablePathProvider;
  final WindowsElevatedRegistryExecutor _elevatedRegistryExecutor;
  final IStartupRunValueRegistryReader _registryReader;
  final IStartupRunValueRegistryWriter _registryWriter;

  @override
  Future<Result<bool>> isEnabled() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    try {
      final queryResults = await _queryStartupRegistry();
      final enabled = _hasHealthyCurrentUserEntry(queryResults);

      developer.log(
        'Auto-start status: $enabled',
        name: 'startup_service',
        level: 800,
      );

      return Success(enabled);
    } on StartupServiceFailure catch (error, stackTrace) {
      developer.log(
        'Failed to query auto-start status',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(error);
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
    bool createIfMissing = true,
  }) async {
    if (!_isWindows()) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    try {
      return await _evaluateLaunchConfiguration(
        allowElevation: allowElevation,
        createIfMissing: createIfMissing,
      );
    } on StartupServiceFailure catch (error, stackTrace) {
      developer.log(
        'Failed to validate auto-start launch configuration',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(error);
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
    required bool createIfMissing,
  }) async {
    final queryResults = await _queryStartupRegistry();
    if (!_needsRepair(queryResults)) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    final existingEntries = queryResults.where((result) => result.exists).toList();
    final hasUnreadableMachine = queryResults.any((result) => result.isMachineScopeUnreadable);
    final onlyMissingHkcu = existingEntries.isEmpty && !hasUnreadableMachine;
    if (onlyMissingHkcu && !createIfMissing) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    developer.log(
      allowElevation
          ? 'Auto-start entry is stale, duplicated, missing, or not HKCU-first. Repairing.'
          : 'Auto-start entry needs repair. Repairing HKCU without elevation.',
      name: 'startup_service',
      level: 800,
    );

    return _repairStartupEntries(
      queryResults,
      allowElevation: allowElevation,
    );
  }

  @override
  Future<Result<Unit>> enable() async {
    if (!_isWindows()) {
      return Failure(
        StartupServiceFailure(
          message: 'Auto-start is not supported on this platform.',
          startupCode: StartupServiceFailureCode.unsupportedPlatform,
        ),
      );
    }

    try {
      final queryResults = await _queryStartupRegistry();
      if (_hasHealthyCurrentUserEntry(queryResults)) {
        developer.log(
          'Auto-start already has a healthy HKCU registry entry',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      return await _writeStartupEntry(StartupRegistryScope.currentUser);
    } on StartupServiceFailure catch (error, stackTrace) {
      developer.log(
        'Failed to enable auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(error);
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
      final scopesToDelete = <StartupRegistryScope>{
        for (final result in queryResults)
          if (result.exists || result.isMachineScopeUnreadable) result.scope,
      };

      for (final scope in scopesToDelete) {
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
    } on StartupServiceFailure catch (error, stackTrace) {
      developer.log(
        'Failed to disable auto-start',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(error);
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
  Future<Result<String>> buildStartupDiagnosticReport() async {
    if (!_isWindows()) {
      return Failure(
        StartupServiceFailure(
          message: 'Startup diagnostics are only available on Windows.',
          startupCode: StartupServiceFailureCode.unsupportedPlatform,
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
        } else if (result.readResult.status == StartupRunValueReadStatus.failed) {
          buffer.writeln('  Read failed (Win32 status: ${result.readResult.nativeStatus})');
        } else if (result.readResult.status == StartupRunValueReadStatus.accessDenied) {
          buffer.writeln('  Read denied (Win32 status: ${result.readResult.nativeStatus})');
        }
        buffer.writeln();
      }

      final existing = queryResults.where((result) => result.exists).toList();
      final unreadable = queryResults
          .where((result) => result.isMachineScopeUnreadable)
          .map((result) => result.scope.label)
          .join(', ');
      buffer
        ..writeln('Needs repair: ${_needsRepair(queryResults)}')
        ..writeln('Unreadable machine scopes: ${unreadable.isEmpty ? 'none' : unreadable}');
      // Keep existing count available for operators reading the report.
      buffer.writeln('Existing entry count: ${existing.length}');

      return Success(buffer.toString().trimRight());
    } on StartupServiceFailure catch (error, stackTrace) {
      developer.log(
        'Failed to build startup diagnostic report',
        name: 'startup_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(error);
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
      final readResult = _registryReader.read(
        scope: scope,
        valueName: runValueName,
      );

      switch (readResult.status) {
        case StartupRunValueReadStatus.accessDenied:
        case StartupRunValueReadStatus.failed:
          if (scope.isMachineScope) {
            developer.log(
              'Machine-scope startup registry read unavailable in ${scope.label} '
              '(status: ${readResult.status.name}, native: ${readResult.nativeStatus}).',
              name: 'startup_service',
              level: 800,
            );
            results.add(
              _StartupRegistryQueryResult(
                scope: scope,
                readResult: readResult,
                entry: null,
              ),
            );
            continue;
          }
          if (readResult.status == StartupRunValueReadStatus.accessDenied) {
            throw StartupServiceFailure(
              message: 'Permission denied when querying auto-start in ${scope.label}.',
              startupCode: StartupServiceFailureCode.accessDenied,
              registryScopeLabel: scope.label,
              nativeStatus: readResult.nativeStatus,
            );
          }
          throw StartupServiceFailure(
            message: 'Failed when querying auto-start in ${scope.label}.',
            startupCode: StartupServiceFailureCode.registryReadFailed,
            registryScopeLabel: scope.label,
            nativeStatus: readResult.nativeStatus,
          );
        case StartupRunValueReadStatus.notFound:
        case StartupRunValueReadStatus.found:
          break;
      }

      final rawValue = readResult.value;
      results.add(
        _StartupRegistryQueryResult(
          scope: scope,
          readResult: readResult,
          entry: rawValue == null
              ? null
              : StartupRegistryEntry.fromRawValue(
                  scope: scope,
                  valueName: runValueName,
                  rawValue: rawValue,
                ),
        ),
      );
    }
    return results;
  }

  /// Healthy auto-start means exactly one Run entry: a healthy HKCU value.
  /// Any machine-scope entry (including unreadable) or missing/unhealthy HKCU
  /// requires repair.
  bool _needsRepair(List<_StartupRegistryQueryResult> queryResults) {
    if (queryResults.any((result) => result.isMachineScopeUnreadable)) {
      return true;
    }

    final expectedExecutable = _executablePathProvider();
    final existingEntries = queryResults.where((result) => result.exists).toList();
    final hasMachineEntry = existingEntries.any((result) => result.scope.isMachineScope);
    if (hasMachineEntry) {
      return true;
    }

    final hkcuEntries = existingEntries
        .where((result) => result.scope == StartupRegistryScope.currentUser)
        .toList();
    if (hkcuEntries.length != 1) {
      return true;
    }

    return !(hkcuEntries.single.entry?.isHealthyFor(expectedExecutable) ?? false);
  }

  bool _hasHealthyCurrentUserEntry(List<_StartupRegistryQueryResult> entries) {
    final expectedExecutable = _executablePathProvider();
    return entries.any(
      (result) =>
          result.scope == StartupRegistryScope.currentUser && (result.entry?.isHealthyFor(expectedExecutable) ?? false),
    );
  }

  Future<Result<StartupLaunchConfigurationStatus>> _repairStartupEntries(
    List<_StartupRegistryQueryResult> queryResults, {
    required bool allowElevation,
  }) async {
    final hasHealthyCurrentUserEntry = _hasHealthyCurrentUserEntry(queryResults);

    if (!hasHealthyCurrentUserEntry) {
      final writeResult = await _writeStartupEntry(StartupRegistryScope.currentUser);
      if (writeResult.isError()) {
        return Failure(writeResult.exceptionOrNull()! as StartupServiceFailure);
      }
    }

    var legacyMachineEntryRemains = false;
    for (final scope in StartupRegistryScope.machineScopes) {
      _StartupRegistryQueryResult? scopeResult;
      for (final result in queryResults) {
        if (result.scope == scope) {
          scopeResult = result;
          break;
        }
      }
      final shouldClean = scopeResult != null && (scopeResult.exists || scopeResult.isMachineScopeUnreadable);
      if (!shouldClean) {
        continue;
      }

      if (!allowElevation) {
        legacyMachineEntryRemains = true;
        developer.log(
          'Skipping elevated cleanup for machine startup entry (${scope.label}).',
          name: 'startup_service',
          level: 800,
        );
        continue;
      }

      final deleteResult = await _deleteStartupEntry(scope);
      if (deleteResult.isError()) {
        if (_hasHealthyCurrentUserEntry(queryResults) || await _hasHealthyCurrentUserEntryAfterQuery()) {
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

    return _resolveStatusAfterRepair(legacyMachineEntryRemains: legacyMachineEntryRemains);
  }

  Future<bool> _hasHealthyCurrentUserEntryAfterQuery() async {
    final queryResults = await _queryStartupRegistry();
    return _hasHealthyCurrentUserEntry(queryResults);
  }

  Future<Result<StartupLaunchConfigurationStatus>> _resolveStatusAfterRepair({
    required bool legacyMachineEntryRemains,
  }) async {
    try {
      final queryResults = await _queryStartupRegistry();
      final needsRepair = _needsRepair(queryResults);
      final hasHealthyCurrentUser = _hasHealthyCurrentUserEntry(queryResults);

      if (!needsRepair) {
        if (legacyMachineEntryRemains) {
          return const Success(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry);
        }
        return const Success(StartupLaunchConfigurationStatus.repaired);
      }

      if (legacyMachineEntryRemains && hasHealthyCurrentUser) {
        return const Success(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry);
      }

      return const Success(StartupLaunchConfigurationStatus.needsRepair);
    } on StartupServiceFailure catch (error) {
      return Failure(error);
    }
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

    final writeResult = _registryWriter.setRunValue(
      scope: scope,
      valueName: runValueName,
      rawValueData: valueData,
    );
    if (writeResult.status == StartupRunValueWriteStatus.success) {
      developer.log(
        'Auto-start enabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(_failureFromWriteResult(result: writeResult, action: 'enabling auto-start', scope: scope));
  }

  Future<Result<Unit>> _deleteStartupEntry(StartupRegistryScope scope) async {
    if (scope.requiresElevation) {
      final win32Result = _registryWriter.deleteRunValue(
        scope: scope,
        valueName: runValueName,
      );
      if (win32Result.status == StartupRunValueWriteStatus.success ||
          win32Result.status == StartupRunValueWriteStatus.notFound) {
        developer.log(
          'Auto-start disabled successfully (${scope.label})',
          name: 'startup_service',
          level: 800,
        );
        return const Success(unit);
      }

      if (win32Result.status != StartupRunValueWriteStatus.accessDenied) {
        return Failure(
          _failureFromWriteResult(
            result: win32Result,
            action: 'disabling auto-start',
            scope: scope,
            isWrite: false,
          ),
        );
      }

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

    final writeResult = _registryWriter.deleteRunValue(
      scope: scope,
      valueName: runValueName,
    );
    if (writeResult.status == StartupRunValueWriteStatus.success ||
        writeResult.status == StartupRunValueWriteStatus.notFound) {
      developer.log(
        'Auto-start disabled successfully (${scope.label})',
        name: 'startup_service',
        level: 800,
      );
      return const Success(unit);
    }

    return Failure(
      _failureFromWriteResult(
        result: writeResult,
        action: 'disabling auto-start',
        scope: scope,
        isWrite: false,
      ),
    );
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
      startupCode: code,
      registryScopeLabel: scope.label,
    );
  }

  StartupServiceFailure _failureFromWriteResult({
    required StartupRunValueWriteResult result,
    required String action,
    required StartupRegistryScope scope,
    bool isWrite = true,
  }) {
    final code = switch (result.status) {
      StartupRunValueWriteStatus.accessDenied => StartupServiceFailureCode.accessDenied,
      StartupRunValueWriteStatus.failed =>
        isWrite ? StartupServiceFailureCode.registryWriteFailed : StartupServiceFailureCode.registryDeleteFailed,
      StartupRunValueWriteStatus.notFound || StartupRunValueWriteStatus.success => StartupServiceFailureCode.unknown,
    };
    final message = switch (result.status) {
      StartupRunValueWriteStatus.accessDenied => 'Permission denied when $action in ${scope.label}.',
      _ => 'Failed when $action in ${scope.label}.',
    };
    developer.log(
      message,
      name: 'startup_service',
      level: 900,
    );
    return StartupServiceFailure(
      message: message,
      startupCode: code,
      registryScopeLabel: scope.label,
      nativeStatus: result.nativeStatus,
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
    required this.readResult,
    required this.entry,
  });

  final StartupRegistryScope scope;
  final StartupRunValueReadResult readResult;
  final StartupRegistryEntry? entry;

  bool get exists =>
      readResult.status == StartupRunValueReadStatus.found && (readResult.value?.isNotEmpty ?? false);

  bool get isMachineScopeUnreadable =>
      scope.isMachineScope &&
      (readResult.status == StartupRunValueReadStatus.accessDenied ||
          readResult.status == StartupRunValueReadStatus.failed);
}
