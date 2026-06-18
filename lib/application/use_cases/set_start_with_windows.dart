import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
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
        launchConfiguration = await StartupLaunchConfigurationMapper.validate(
          _repository,
        );
      }
    }

    final persistResult = await _repository.persistStartWithWindows(value);
    return persistResult.fold(
      (_) => Success(
        SetStartWithWindowsOutcome(
          change: value ? StartupChangeOutcome.enabled : StartupChangeOutcome.disabled,
          launchConfiguration: launchConfiguration,
        ),
      ),
      (failure) {
        developer.log(
          'Failed to persist startWithWindows after system toggle: $failure',
          name: 'set_start_with_windows',
          level: 900,
        );
        return Failure(failure);
      },
    );
  }
}
