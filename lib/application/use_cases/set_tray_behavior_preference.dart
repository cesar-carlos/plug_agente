import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class SetTrayBehaviorPreference {
  SetTrayBehaviorPreference(
    this._repository, {
    IWindowManagerService? windowManagerService,
    ITrayService? trayService,
  }) : _windowManagerService = windowManagerService,
       _trayService = trayService;

  final IStartupPreferencesRepository _repository;
  final IWindowManagerService? _windowManagerService;
  final ITrayService? _trayService;

  Future<Result<bool>> call(TrayBehaviorKind kind, bool value) async {
    final trayService = _trayService;
    if (trayService == null || !trayService.isReady) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Tray behavior is unavailable for this session.',
          code: 'TRAY_UNAVAILABLE',
          context: {'availability': trayService?.availability.name ?? 'unregistered'},
        ),
      );
    }

    final windowManagerService = _windowManagerService;
    if (windowManagerService == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Window manager is unavailable for this session.',
          code: 'TRAY_BEHAVIOR_APPLY_FAILED',
          context: const {'operation': 'apply_tray_behavior'},
        ),
      );
    }

    final previousValue = switch (kind) {
      TrayBehaviorKind.minimizeToTray => _repository.minimizeToTray,
      TrayBehaviorKind.closeToTray => _repository.closeToTray,
    };
    final runtimeResult = switch (kind) {
      TrayBehaviorKind.minimizeToTray => await windowManagerService.setMinimizeToTray(value: value),
      TrayBehaviorKind.closeToTray => await windowManagerService.setCloseToTray(value: value),
    };
    if (runtimeResult.isError()) {
      return Failure(runtimeResult.exceptionOrNull()!);
    }

    final persistResult = switch (kind) {
      TrayBehaviorKind.minimizeToTray => await _repository.persistMinimizeToTray(value),
      TrayBehaviorKind.closeToTray => await _repository.persistCloseToTray(value),
    };

    if (persistResult.isSuccess()) {
      return Success(value);
    }

    final failure = persistResult.exceptionOrNull()!;
    final rollbackResult = switch (kind) {
      TrayBehaviorKind.minimizeToTray => await windowManagerService.setMinimizeToTray(value: previousValue),
      TrayBehaviorKind.closeToTray => await windowManagerService.setCloseToTray(value: previousValue),
    };
    developer.log(
      'Failed to persist tray behavior preference: $failure '
      '(runtime rollback: ${rollbackResult.isSuccess() ? 'succeeded' : 'failed'})',
      name: 'set_tray_behavior_preference',
      level: 900,
    );
    if (rollbackResult.isError()) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Could not save tray behavior and restore the previous window behavior.',
          code: 'TRAY_BEHAVIOR_APPLY_FAILED',
          cause: failure,
          context: const {'operation': 'rollback_tray_behavior'},
        ),
      );
    }
    return Failure(failure);
  }
}
