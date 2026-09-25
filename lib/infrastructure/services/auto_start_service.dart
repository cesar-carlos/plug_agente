import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_executable_eligibility.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_diagnostic_report.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_snapshot.dart';
import 'package:plug_agente/infrastructure/services/startup_run_entry_mutator.dart';
import 'package:plug_agente/infrastructure/services/windows_elevated_registry_executor.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';
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
    IStartupApprovedStore? startupApprovedStore,
  }) : _processStarter = processStarter ?? _defaultProcessStarter,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _executablePathProvider = executablePathProvider ?? (() => Platform.resolvedExecutable),
       _snapshotReader = StartupRegistrySnapshotReader(registryReader ?? const Win32StartupRunValueRegistryReader()),
       _runEntryMutator = StartupRunEntryMutator(
         registryWriter: registryWriter ?? const Win32StartupRunValueRegistryWriter(),
         elevatedRegistryExecutor:
             elevatedRegistryExecutor ?? WindowsElevatedRegistryExecutor(processRunner: processRunner),
         valueName: runValueName,
       ),
       _startupApprovedStore = startupApprovedStore ?? const Win32StartupApprovedStore();

  static const String runValueName = 'Plug Agente';

  final DetachedProcessStarter _processStarter;
  final WindowsPlatformResolver _isWindows;
  final ExecutablePathProvider _executablePathProvider;
  final StartupRegistrySnapshotReader _snapshotReader;
  final StartupRunEntryMutator _runEntryMutator;
  final IStartupApprovedStore _startupApprovedStore;

  @override
  Future<Result<bool>> isEnabled() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    return _guard('Failed to query auto-start status', () async {
      final expectedExecutable = _executablePathProvider();
      final snapshot = _readSnapshot();
      final hasHealthyRunEntry = snapshot.hasHealthyCurrentUserEntry(expectedExecutable);
      final approved = _readStartupApproved();
      final enabled = hasHealthyRunEntry && !approved.isEffectivelyDisabled;

      developer.log(
        'Auto-start status: $enabled '
        '(runHealthy: $hasHealthyRunEntry, startupApproved: ${approved.status.name})',
        name: 'startup_service',
        level: 800,
      );
      return Success(enabled);
    });
  }

  @override
  Future<Result<bool>> isDisabledByStartupApps() async {
    if (!_isWindows()) {
      return const Success(false);
    }

    // Unclassifiable overlays count as a user choice so boot/sync never
    // silently overwrite them; an explicit enable still rewrites the value.
    return _guard(
      'Failed to query Startup Apps disable state',
      () async => Success(_readStartupApproved().isEffectivelyDisabled),
    );
  }

  @override
  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
    bool createIfMissing = true,
  }) async {
    if (!_isWindows()) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    return _guard(
      'Failed to validate auto-start launch configuration',
      () => _evaluateLaunchConfiguration(
        allowElevation: allowElevation,
        createIfMissing: createIfMissing,
      ),
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

    return _guard('Failed to enable auto-start', _enableCurrentUserEntry);
  }

  @override
  Future<Result<Unit>> disable() async {
    if (!_isWindows()) {
      return const Success(unit);
    }

    return _guard('Failed to disable auto-start', _disableAllEntries);
  }

  @override
  Future<Result<Unit>> openSystemSettings() async {
    if (!_isWindows()) {
      return const Success(unit);
    }

    return _guard('Failed to open Windows startup settings', () async {
      await _processStarter(
        'cmd',
        const <String>['/c', 'start', '', 'ms-settings:startupapps'],
        mode: ProcessStartMode.detached,
      );
      developer.log('Opened Windows startup settings', name: 'startup_service', level: 800);
      return const Success(unit);
    });
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

    return _guard('Failed to build startup diagnostic report', () async {
      return Success(
        StartupRegistryDiagnosticReport.render(
          expectedExecutable: _executablePathProvider(),
          snapshot: _readSnapshot(),
          approved: _readStartupApproved(),
        ),
      );
    });
  }

  Future<Result<T>> _guard<T extends Object>(
    String failureMessage,
    Future<Result<T>> Function() body,
  ) async {
    try {
      return await body();
    } on StartupServiceFailure catch (error, stackTrace) {
      _logFailure(failureMessage, error, stackTrace);
      return Failure(error);
    } on Exception catch (error, stackTrace) {
      _logFailure(failureMessage, error, stackTrace);
      return Failure(StartupServiceFailure(message: failureMessage, cause: error));
    }
  }

  void _logFailure(String message, Object error, StackTrace stackTrace) {
    developer.log(message, name: 'startup_service', level: 900, error: error, stackTrace: stackTrace);
  }

  Future<Result<Unit>> _enableCurrentUserEntry() async {
    final currentExecutable = _executablePathProvider();
    if (isNonProductionStartupExecutable(currentExecutable)) {
      return _nonProductionExecutableFailure();
    }

    final snapshot = _readSnapshot();
    if (!canPersistStartupExecutable(
      currentExecutable,
      existingHealthyExecutablePath: snapshot.currentUserExecutablePath,
    )) {
      return _nonProductionExecutableFailure();
    }

    var wroteRunEntry = false;
    if (!snapshot.hasHealthyCurrentUserEntry(currentExecutable)) {
      final writeResult = _writeCurrentUserEntry();
      if (writeResult.isError()) {
        return writeResult;
      }
      wroteRunEntry = true;
    } else {
      developer.log('Auto-start already has a healthy HKCU registry entry', name: 'startup_service', level: 800);
    }

    final approvedResult = _ensureStartupApprovedEnabled(forceWrite: true);
    if (approvedResult.isError()) {
      if (wroteRunEntry) {
        await _rollbackCurrentUserRunEntry();
      }
      return approvedResult;
    }

    final verified = _confirmEnabled();
    if (verified.isError() && wroteRunEntry) {
      await _rollbackCurrentUserRunEntry();
    }
    return verified;
  }

  Future<Result<Unit>> _disableAllEntries() async {
    final existingScopes = {for (final result in _readSnapshot().existing) result.scope};
    // Machine scopes first: if UAC is declined, HKCU stays intact and the
    // toggle keeps matching what Windows will actually launch.
    final scopesToDelete = <StartupRegistryScope>[
      ...existingScopes.where((scope) => scope.isMachineScope),
      ...existingScopes.where((scope) => !scope.isMachineScope),
    ];

    for (final scope in scopesToDelete) {
      final deleteResult = await _runEntryMutator.delete(scope);
      if (deleteResult.isError()) {
        return deleteResult;
      }
    }

    _deleteStartupApprovedBestEffort();

    final verified = _confirmDisabled();
    if (verified.isSuccess()) {
      developer.log('Auto-start disabled successfully', name: 'startup_service', level: 800);
    }
    return verified;
  }

  Future<Result<StartupLaunchConfigurationStatus>> _evaluateLaunchConfiguration({
    required bool allowElevation,
    required bool createIfMissing,
  }) async {
    final currentExecutable = _executablePathProvider();
    if (isNonProductionStartupExecutable(currentExecutable)) {
      developer.log(
        'Skipping auto-start repair because the current executable is a debug/profile build.',
        name: 'startup_service',
        level: 800,
      );
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    final snapshot = _readSnapshot();
    if (!canPersistStartupExecutable(
      currentExecutable,
      existingHealthyExecutablePath: snapshot.currentUserExecutablePath,
    )) {
      developer.log(
        'Skipping auto-start repair because the current executable must not overwrite an installed Run key.',
        name: 'startup_service',
        level: 800,
      );
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    final approved = _readStartupApproved();
    if (!snapshot.needsRepair(approved: approved, expectedExecutable: currentExecutable)) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    final onlyMissingHkcu = snapshot.existing.isEmpty && !approved.isEffectivelyDisabled;
    if (onlyMissingHkcu && !createIfMissing) {
      return const Success(StartupLaunchConfigurationStatus.unchanged);
    }

    developer.log(
      allowElevation
          ? 'Auto-start entry is stale, duplicated, missing, blocked by Startup Apps, '
                'or not HKCU-first. Repairing.'
          : 'Auto-start entry needs repair. Repairing HKCU / StartupApproved without elevation.',
      name: 'startup_service',
      level: 800,
    );

    return _repairStartupEntries(snapshot, allowElevation: allowElevation, approved: approved);
  }

  Future<Result<StartupLaunchConfigurationStatus>> _repairStartupEntries(
    StartupRegistrySnapshot snapshot, {
    required bool allowElevation,
    required StartupApprovedReadResult approved,
  }) async {
    final expectedExecutable = _executablePathProvider();

    var wroteRunEntry = false;
    if (!snapshot.hasHealthyCurrentUserEntry(expectedExecutable)) {
      final writeResult = _writeCurrentUserEntry();
      if (writeResult.isError()) {
        return Failure(writeResult.exceptionOrNull()!);
      }
      wroteRunEntry = true;
    }

    if (wroteRunEntry || approved.isEffectivelyDisabled) {
      final approvedResult = _ensureStartupApprovedEnabled(forceWrite: true);
      if (approvedResult.isError()) {
        if (wroteRunEntry) {
          await _rollbackCurrentUserRunEntry();
        }
        return Failure(approvedResult.exceptionOrNull()!);
      }
    }

    var legacyMachineEntryRemains = false;
    for (final scope in StartupRegistryScope.machineScopes) {
      // Only clean machine scopes that actually expose an entry. Unreadable
      // scopes alone must not drive elevated delete / legacy notices.
      if (!(snapshot.resultFor(scope)?.exists ?? false)) {
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

      final deleteResult = await _runEntryMutator.delete(scope);
      if (deleteResult.isError()) {
        if (snapshot.hasHealthyCurrentUserEntry(expectedExecutable) ||
            _readSnapshot().hasHealthyCurrentUserEntry(expectedExecutable)) {
          legacyMachineEntryRemains = true;
          developer.log(
            'Could not remove legacy machine startup entry (${scope.label}); HKCU entry is healthy.',
            name: 'startup_service',
            level: 800,
          );
          continue;
        }
        return Failure(deleteResult.exceptionOrNull()!);
      }
    }

    return _resolveStatusAfterRepair(legacyMachineEntryRemains: legacyMachineEntryRemains);
  }

  Result<StartupLaunchConfigurationStatus> _resolveStatusAfterRepair({
    required bool legacyMachineEntryRemains,
  }) {
    final expectedExecutable = _executablePathProvider();
    final snapshot = _readSnapshot();
    final approved = _readStartupApproved();

    if (!snapshot.needsRepair(approved: approved, expectedExecutable: expectedExecutable)) {
      return Success(
        legacyMachineEntryRemains
            ? StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry
            : StartupLaunchConfigurationStatus.repaired,
      );
    }

    if (legacyMachineEntryRemains &&
        snapshot.hasHealthyCurrentUserEntry(expectedExecutable) &&
        !approved.isEffectivelyDisabled) {
      return const Success(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry);
    }

    return const Success(StartupLaunchConfigurationStatus.needsRepair);
  }

  Result<Unit> _writeCurrentUserEntry() {
    final executablePath = _executablePathProvider();
    if (!canPersistStartupExecutable(executablePath)) {
      return _nonProductionExecutableFailure();
    }
    return _runEntryMutator.writeCurrentUser('"$executablePath" "${LaunchArgsConstants.autostartArg}"');
  }

  Result<Unit> _ensureStartupApprovedEnabled({bool forceWrite = false}) {
    final current = _readStartupApproved();
    if (!forceWrite && current.isEffectivelyEnabled) {
      return const Success(unit);
    }

    if (current.status == StartupApprovedStatus.accessDenied && !forceWrite) {
      return Failure(
        StartupServiceFailure(
          message: 'Permission denied when enabling Startup Apps approval.',
          startupCode: StartupServiceFailureCode.accessDenied,
          registryScopeLabel: 'StartupApproved',
          nativeStatus: current.nativeStatus,
        ),
      );
    }

    final writeResult = _startupApprovedStore.writeEnabled(valueName: runValueName);
    if (writeResult.status != StartupApprovedWriteStatus.success) {
      return Failure(
        StartupServiceFailure(
          message: 'Failed when enabling Startup Apps approval.',
          startupCode: writeResult.status == StartupApprovedWriteStatus.accessDenied
              ? StartupServiceFailureCode.accessDenied
              : StartupServiceFailureCode.registryWriteFailed,
          registryScopeLabel: 'StartupApproved',
          nativeStatus: writeResult.nativeStatus,
        ),
      );
    }

    final verified = _readStartupApproved();
    if (!verified.isEffectivelyEnabled) {
      return Failure(
        StartupServiceFailure(
          message: 'Startup Apps approval write succeeded but read-back is still blocked.',
          startupCode: StartupServiceFailureCode.registryWriteFailed,
          registryScopeLabel: 'StartupApproved',
          nativeStatus: verified.nativeStatus,
        ),
      );
    }

    developer.log('StartupApproved enabled for $runValueName', name: 'startup_service', level: 800);
    return const Success(unit);
  }

  Result<Unit> _confirmEnabled() {
    final expectedExecutable = _executablePathProvider();
    if (_readSnapshot().hasHealthyCurrentUserEntry(expectedExecutable) &&
        !_readStartupApproved().isEffectivelyDisabled) {
      return const Success(unit);
    }

    return Failure(
      StartupServiceFailure(
        message: 'Auto-start entry could not be verified after writing the registry.',
        startupCode: StartupServiceFailureCode.registryWriteFailed,
      ),
    );
  }

  Result<Unit> _confirmDisabled() {
    if (!_readSnapshot().hasHealthyCurrentUserEntry(_executablePathProvider())) {
      return const Success(unit);
    }

    return Failure(
      StartupServiceFailure(
        message: 'Auto-start entry is still present after disable.',
        startupCode: StartupServiceFailureCode.registryDeleteFailed,
        registryScopeLabel: StartupRegistryScope.currentUser.label,
      ),
    );
  }

  Future<void> _rollbackCurrentUserRunEntry() async {
    final deleteResult = await _runEntryMutator.delete(StartupRegistryScope.currentUser);
    deleteResult.fold(
      (_) => developer.log(
        'Rolled back HKCU auto-start entry after a failed enable',
        name: 'startup_service',
        level: 800,
      ),
      (failure) => developer.log(
        'Failed to roll back HKCU auto-start entry after a failed enable: $failure',
        name: 'startup_service',
        level: 900,
      ),
    );
  }

  void _deleteStartupApprovedBestEffort() {
    final deleteResult = _startupApprovedStore.delete(valueName: runValueName);
    if (deleteResult.status == StartupApprovedWriteStatus.success) {
      developer.log('StartupApproved overlay removed for $runValueName', name: 'startup_service', level: 800);
      return;
    }

    developer.log(
      'Failed to remove StartupApproved overlay for $runValueName '
      '(status: ${deleteResult.status.name}, native: ${deleteResult.nativeStatus})',
      name: 'startup_service',
      level: 900,
    );
  }

  Result<Unit> _nonProductionExecutableFailure() {
    return Failure(
      StartupServiceFailure(
        message: 'Auto-start cannot persist this executable as the Windows startup command.',
        startupCode: StartupServiceFailureCode.nonProductionExecutable,
      ),
    );
  }

  StartupRegistrySnapshot _readSnapshot() => _snapshotReader.read(valueName: runValueName);

  StartupApprovedReadResult _readStartupApproved() => _startupApprovedStore.read(valueName: runValueName);

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(executable, arguments, mode: mode);
  }
}
