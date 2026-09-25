import 'dart:developer' as developer;

import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';

class StartupRegistryQueryResult {
  const StartupRegistryQueryResult({
    required this.scope,
    required this.readResult,
    required this.entry,
  });

  final StartupRegistryScope scope;
  final StartupRunValueReadResult readResult;
  final StartupRegistryEntry? entry;

  bool get exists => readResult.status == StartupRunValueReadStatus.found && (readResult.value?.isNotEmpty ?? false);

  bool get isMachineScopeUnreadable =>
      scope.isMachineScope &&
      (readResult.status == StartupRunValueReadStatus.accessDenied ||
          readResult.status == StartupRunValueReadStatus.failed);
}

/// One read of every Run scope for the auto-start value.
class StartupRegistrySnapshot {
  const StartupRegistrySnapshot(this.results);

  final List<StartupRegistryQueryResult> results;

  Iterable<StartupRegistryQueryResult> get existing => results.where((result) => result.exists);

  bool get hasMachineEntry => existing.any((result) => result.scope.isMachineScope);

  StartupRegistryQueryResult? resultFor(StartupRegistryScope scope) {
    for (final result in results) {
      if (result.scope == scope) {
        return result;
      }
    }
    return null;
  }

  bool hasHealthyCurrentUserEntry(String expectedExecutable) {
    return resultFor(StartupRegistryScope.currentUser)?.entry?.isHealthyFor(expectedExecutable) ?? false;
  }

  String? get currentUserExecutablePath {
    final path = resultFor(StartupRegistryScope.currentUser)?.entry?.executablePath.trim();
    return path == null || path.isEmpty ? null : path;
  }

  /// Healthy auto-start means exactly one Run entry: a healthy HKCU value,
  /// not blocked by StartupApproved, and no machine-scope Run duplicates.
  ///
  /// Unreadable machine scopes alone do not force repair: they are common on
  /// locked-down machines and must not surface false "legacy entry" notices when
  /// HKCU is already healthy.
  bool needsRepair({
    required StartupApprovedReadResult approved,
    required String expectedExecutable,
  }) {
    if (approved.isEffectivelyDisabled || hasMachineEntry) {
      return true;
    }
    return !hasHealthyCurrentUserEntry(expectedExecutable);
  }
}

class StartupRegistrySnapshotReader {
  const StartupRegistrySnapshotReader(this._registryReader);

  final IStartupRunValueRegistryReader _registryReader;

  /// Throws [StartupServiceFailure] when HKCU cannot be read; machine scopes
  /// that cannot be read are kept as unreadable results.
  StartupRegistrySnapshot read({required String valueName}) {
    return StartupRegistrySnapshot([
      for (final scope in StartupRegistryScope.values) _readScope(scope, valueName),
    ]);
  }

  StartupRegistryQueryResult _readScope(StartupRegistryScope scope, String valueName) {
    final readResult = _registryReader.read(scope: scope, valueName: valueName);

    switch (readResult.status) {
      case StartupRunValueReadStatus.accessDenied:
      case StartupRunValueReadStatus.failed:
        if (!scope.isMachineScope) {
          throw _currentUserReadFailure(scope, readResult);
        }
        developer.log(
          'Machine-scope startup registry read unavailable in ${scope.label} '
          '(status: ${readResult.status.name}, native: ${readResult.nativeStatus}).',
          name: 'startup_service',
          level: 800,
        );
        return StartupRegistryQueryResult(scope: scope, readResult: readResult, entry: null);
      case StartupRunValueReadStatus.notFound:
      case StartupRunValueReadStatus.found:
        final rawValue = readResult.value;
        return StartupRegistryQueryResult(
          scope: scope,
          readResult: readResult,
          entry: rawValue == null
              ? null
              : StartupRegistryEntry.fromRawValue(
                  scope: scope,
                  valueName: valueName,
                  rawValue: rawValue,
                ),
        );
    }
  }

  StartupServiceFailure _currentUserReadFailure(
    StartupRegistryScope scope,
    StartupRunValueReadResult readResult,
  ) {
    if (readResult.status == StartupRunValueReadStatus.accessDenied) {
      return StartupServiceFailure(
        message: 'Permission denied when querying auto-start in ${scope.label}.',
        startupCode: StartupServiceFailureCode.accessDenied,
        registryScopeLabel: scope.label,
        nativeStatus: readResult.nativeStatus,
      );
    }
    return StartupServiceFailure(
      message: 'Failed when querying auto-start in ${scope.label}.',
      startupCode: StartupServiceFailureCode.registryReadFailed,
      registryScopeLabel: scope.label,
      nativeStatus: readResult.nativeStatus,
    );
  }
}
