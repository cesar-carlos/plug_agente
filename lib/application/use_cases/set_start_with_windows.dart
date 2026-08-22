import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class SetStartWithWindows {
  SetStartWithWindows(this._repository);

  final IStartupPreferencesRepository _repository;

  Future<Result<SetStartWithWindowsOutcome>> call(bool value) async {
    StartupLaunchConfigurationOutcome? launchConfiguration;

    if (_repository.isStartupServiceAvailable) {
      final toggleResult = value ? await _repository.enableSystemStartup() : await _repository.disableSystemStartup();

      final toggled = toggleResult.fold(
        (_) {
          developer.log(
            'Startup ${value ? "enabled" : "disabled"} successfully',
            name: 'set_start_with_windows',
            level: 800,
          );
          return true;
        },
        (failure) {
          developer.log(
            'Failed to ${value ? "enable" : "disable"} startup: $failure',
            name: 'set_start_with_windows',
            level: 900,
          );
          return false;
        },
      );

      if (!toggled) {
        return Failure(toggleResult.exceptionOrNull()!);
      }

      if (value) {
        // Do not prompt UAC on toggle; elevated machine cleanup stays on Repair.
        launchConfiguration = await StartupLaunchConfigurationMapper.validate(
          _repository,
          allowElevation: false,
        );
      }
    }

    final persistResult = await _repository.persistStartWithWindows(value);
    if (persistResult.isSuccess()) {
      return Success(
        SetStartWithWindowsOutcome(
          change: value ? StartupChangeOutcome.enabled : StartupChangeOutcome.disabled,
          launchConfiguration: launchConfiguration,
        ),
      );
    }

    final failure = persistResult.exceptionOrNull()!;
    developer.log(
      'Failed to persist startWithWindows after system toggle: $failure',
      name: 'set_start_with_windows',
      level: 900,
    );
    if (_repository.isStartupServiceAvailable) {
      final rollbackResult = await _rollbackSystemStartup(enabled: value);
      if (rollbackResult.isError()) {
        final rollbackFailure = rollbackResult.exceptionOrNull();
        developer.log(
          'Failed to roll back system startup after persist failure: $rollbackFailure',
          name: 'set_start_with_windows',
          level: 900,
        );
        return Failure(
          StartupServiceFailure(
            message: 'Could not save the startup preference, and Windows startup could not be reverted.',
            startupCode: StartupServiceFailureCode.rollbackFailed,
            cause: failure,
          ),
        );
      }
    }
    return Failure(failure);
  }

  Future<Result<Unit>> _rollbackSystemStartup({required bool enabled}) async {
    final rollbackResult = enabled
        ? await _repository.disableSystemStartup()
        : await _repository.enableSystemStartup();
    rollbackResult.fold(
      (_) {
        developer.log(
          'Rolled back system startup after persist failure (reverted enable=$enabled)',
          name: 'set_start_with_windows',
          level: 800,
        );
      },
      (rollbackFailure) {
        developer.log(
          'Failed to roll back system startup after persist failure: $rollbackFailure',
          name: 'set_start_with_windows',
          level: 900,
        );
      },
    );
    return rollbackResult;
  }
}
