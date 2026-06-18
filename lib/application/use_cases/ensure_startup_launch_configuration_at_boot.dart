import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/core/utils/launch_args.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';

class EnsureStartupLaunchConfigurationAtBootOutcome {
  const EnsureStartupLaunchConfigurationAtBootOutcome({
    required this.isAutostartLaunch,
    this.launchConfiguration,
  });

  final bool isAutostartLaunch;
  final StartupLaunchConfigurationOutcome? launchConfiguration;
}

class EnsureStartupLaunchConfigurationAtBoot {
  EnsureStartupLaunchConfigurationAtBoot(this._repository);

  final IStartupPreferencesRepository _repository;

  Future<EnsureStartupLaunchConfigurationAtBootOutcome> call({
    required List<String> launchArgs,
  }) async {
    var effectiveAutostartLaunch = isAutostartLaunch(launchArgs);
    StartupLaunchConfigurationOutcome? launchConfiguration;

    if (!_repository.isStartupServiceAvailable) {
      return EnsureStartupLaunchConfigurationAtBootOutcome(
        isAutostartLaunch: effectiveAutostartLaunch,
      );
    }

    final systemEnabled = await _readSystemEnabled();
    final shouldValidate = _repository.startWithWindows || systemEnabled;

    if (shouldValidate) {
      launchConfiguration = await StartupLaunchConfigurationMapper.validate(
        _repository,
        allowElevation: false,
      );
    }

    if (!effectiveAutostartLaunch && _repository.startMinimized) {
      final missingAutostart = await _hasRegistryEntryMissingAutostart();
      if (missingAutostart) {
        developer.log(
          'Registry startup entry is missing --autostart; treating launch as autostart for minimized startup',
          name: 'ensure_startup_launch_configuration_at_boot',
          level: 800,
        );
        effectiveAutostartLaunch = true;
      }
    }

    return EnsureStartupLaunchConfigurationAtBootOutcome(
      isAutostartLaunch: effectiveAutostartLaunch,
      launchConfiguration: launchConfiguration,
    );
  }

  Future<bool> _readSystemEnabled() async {
    final result = await _repository.readSystemStartupEnabled();
    return result.fold(
      (enabled) => enabled,
      (_) => false,
    );
  }

  Future<bool> _hasRegistryEntryMissingAutostart() async {
    final result = await _repository.hasRegistryEntryMissingAutostartForCurrentExecutable();
    return result.fold(
      (missing) => missing,
      (_) => false,
    );
  }
}
