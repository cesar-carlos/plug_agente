import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_elevated_registry_executor.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_writer.dart';
import 'package:result_dart/result_dart.dart';

/// Writes and deletes the auto-start Run value, elevating only for machine
/// scopes that the current token cannot modify.
class StartupRunEntryMutator {
  const StartupRunEntryMutator({
    required IStartupRunValueRegistryWriter registryWriter,
    required WindowsElevatedRegistryExecutor elevatedRegistryExecutor,
    required String valueName,
  }) : _registryWriter = registryWriter,
       _elevatedRegistryExecutor = elevatedRegistryExecutor,
       _valueName = valueName;

  final IStartupRunValueRegistryWriter _registryWriter;
  final WindowsElevatedRegistryExecutor _elevatedRegistryExecutor;
  final String _valueName;

  Result<Unit> writeCurrentUser(String rawValueData) {
    const scope = StartupRegistryScope.currentUser;
    final writeResult = _registryWriter.setRunValue(
      scope: scope,
      valueName: _valueName,
      rawValueData: rawValueData,
    );
    if (writeResult.status == StartupRunValueWriteStatus.success) {
      _logSuccess('Auto-start enabled successfully', scope);
      return const Success(unit);
    }
    return Failure(_failureFromWriteResult(result: writeResult, action: 'enabling auto-start', scope: scope));
  }

  Future<Result<Unit>> delete(StartupRegistryScope scope) async {
    final writeResult = _registryWriter.deleteRunValue(scope: scope, valueName: _valueName);
    if (_isDeleted(writeResult)) {
      _logSuccess('Auto-start disabled successfully', scope);
      return const Success(unit);
    }

    final canElevate = scope.requiresElevation && writeResult.status == StartupRunValueWriteStatus.accessDenied;
    if (!canElevate) {
      return Failure(
        _failureFromWriteResult(
          result: writeResult,
          action: 'disabling auto-start',
          scope: scope,
          isWrite: false,
        ),
      );
    }

    developer.log(
      'Admin privileges required. Requesting UAC elevation (${scope.label}).',
      name: 'startup_service',
      level: 800,
    );
    final elevatedResult = await _elevatedRegistryExecutor.deleteRunValue(scope: scope, valueName: _valueName);
    if (elevatedResult.exitCode == 0) {
      _logSuccess('Auto-start disabled successfully', scope);
      return const Success(unit);
    }
    return Failure(_failureFromProcessResult(result: elevatedResult, action: 'disabling auto-start', scope: scope));
  }

  bool _isDeleted(StartupRunValueWriteResult result) {
    return result.status == StartupRunValueWriteStatus.success || result.status == StartupRunValueWriteStatus.notFound;
  }

  void _logSuccess(String message, StartupRegistryScope scope) {
    developer.log('$message (${scope.label})', name: 'startup_service', level: 800);
  }

  StartupServiceFailure _failureFromProcessResult({
    required ProcessResult result,
    required String action,
    required StartupRegistryScope scope,
  }) {
    final (code, message) = switch (result) {
      _ when WindowsElevatedRegistryExecutor.isUacCancelled(result) => (
        StartupServiceFailureCode.uacCancelled,
        'UAC authorization cancelled when $action in ${scope.label}.',
      ),
      _ when WindowsElevatedRegistryExecutor.isAccessDenied(result) => (
        StartupServiceFailureCode.accessDenied,
        'Permission denied when $action in ${scope.label}.',
      ),
      _ => (StartupServiceFailureCode.registryDeleteFailed, 'Failed when $action in ${scope.label}.'),
    };
    developer.log(message, name: 'startup_service', level: 900);
    return StartupServiceFailure(
      message: message,
      startupCode: code,
      registryScopeLabel: scope.label,
      nativeStatus: result.exitCode,
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
    developer.log(message, name: 'startup_service', level: 900);
    return StartupServiceFailure(
      message: message,
      startupCode: code,
      registryScopeLabel: scope.label,
      nativeStatus: result.nativeStatus,
    );
  }
}
