import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class SetTrayBehaviorPreference {
  SetTrayBehaviorPreference(
    this._repository, {
    IWindowManagerService? windowManagerService,
  }) : _windowManagerService = windowManagerService;

  final IStartupPreferencesRepository _repository;
  final IWindowManagerService? _windowManagerService;

  Future<Result<bool>> call(TrayBehaviorKind kind, bool value) async {
    final persistResult = switch (kind) {
      TrayBehaviorKind.minimizeToTray => await _repository.persistMinimizeToTray(value),
      TrayBehaviorKind.closeToTray => await _repository.persistCloseToTray(value),
    };

    return persistResult.fold(
      (_) {
        switch (kind) {
          case TrayBehaviorKind.minimizeToTray:
            _windowManagerService?.setMinimizeToTray(value: value);
          case TrayBehaviorKind.closeToTray:
            _windowManagerService?.setCloseToTray(value: value);
        }
        return Success(value);
      },
      (failure) {
        developer.log(
          'Failed to persist tray behavior preference: $failure',
          name: 'set_tray_behavior_preference',
          level: 900,
        );
        return Failure(failure);
      },
    );
  }
}
