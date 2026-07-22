import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
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
  EnsureStartupLaunchConfigurationAtBoot(
    this._repository, {
    StartupConfigurationSessionState? sessionState,
  }) : _sessionState = sessionState;

  final IStartupPreferencesRepository _repository;
  final StartupConfigurationSessionState? _sessionState;

  Future<EnsureStartupLaunchConfigurationAtBootOutcome> call({
    required List<String> launchArgs,
  }) async {
    final isAutostart = isAutostartLaunch(launchArgs);
    StartupLaunchConfigurationOutcome? launchConfiguration;

    if (!_repository.isStartupServiceAvailable) {
      return EnsureStartupLaunchConfigurationAtBootOutcome(
        isAutostartLaunch: isAutostart,
      );
    }

    // Prefer the stored preference to avoid an extra registry read when we
    // already know launch configuration must be validated/repaired.
    final shouldValidate = _repository.startWithWindows || await _readSystemEnabled();
    if (shouldValidate) {
      // ensureLaunchConfiguration now self-heals missing HKCU (writes Run key)
      // and repairs stale/missing --autostart without UAC.
      launchConfiguration = await StartupLaunchConfigurationMapper.validate(
        _repository,
        allowElevation: false,
      );
      if (launchConfiguration != null) {
        developer.log(
          'Startup launch configuration at boot: ${launchConfiguration.type.name}',
          name: 'ensure_startup_launch_configuration_at_boot',
          level: 800,
        );
      }
      // Cache even when unchanged (null) so sync skips a second ensure pass.
      _sessionState?.setBootLaunchConfiguration(launchConfiguration);
    }

    return EnsureStartupLaunchConfigurationAtBootOutcome(
      isAutostartLaunch: isAutostart,
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
}
