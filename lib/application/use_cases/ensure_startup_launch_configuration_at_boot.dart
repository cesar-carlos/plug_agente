import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/core/utils/launch_args.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';
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
    IInstallerAutostartRequestStore? installerAutostartRequestStore,
  }) : _sessionState = sessionState,
       _installerAutostartRequestStore = installerAutostartRequestStore;

  final IStartupPreferencesRepository _repository;
  final StartupConfigurationSessionState? _sessionState;
  final IInstallerAutostartRequestStore? _installerAutostartRequestStore;

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
    // Runs for manual and `--autostart` login launches so an elevated install
    // can heal HKCU for the interactive user at first Windows login.
    final installerRequested = await _applyInstallerAutostartRequest();
    if (!installerRequested && await _readUserDisabledStartup()) {
      await _persistUserDisabledStartup();
      return EnsureStartupLaunchConfigurationAtBootOutcome(
        isAutostartLaunch: isAutostart,
      );
    }

    final shouldValidate =
        installerRequested || _repository.startWithWindows || await _readSystemEnabled();
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

  Future<bool> _applyInstallerAutostartRequest() async {
    final store = _installerAutostartRequestStore;
    if (store == null || !_repository.isStartupServiceAvailable) {
      return false;
    }

    final pending = await store.hasPendingRequest();
    if (!pending) {
      return false;
    }

    developer.log(
      'Installer requested per-user auto-start; registering HKCU for the current user',
      name: 'ensure_startup_launch_configuration_at_boot',
      level: 800,
    );

    final enableResult = await _repository.enableSystemStartup();
    if (enableResult.isError()) {
      developer.log(
        'Failed to honor installer auto-start request for the current user: ${enableResult.exceptionOrNull()}',
        name: 'ensure_startup_launch_configuration_at_boot',
        level: 900,
      );
      return false;
    }

    final persistResult = await _repository.persistStartWithWindows(true);
    if (persistResult.isError()) {
      developer.log(
        'Enabled installer auto-start but failed to persist preference: ${persistResult.exceptionOrNull()}',
        name: 'ensure_startup_launch_configuration_at_boot',
        level: 900,
      );
      return true;
    }

    await store.clearPendingRequest();
    return true;
  }

  Future<bool> _readUserDisabledStartup() async {
    final result = await _repository.readStartupDisabledByUser();
    return result.fold(
      (disabled) => disabled,
      (failure) {
        developer.log(
          'Failed to read Startup Apps disable state at boot: $failure',
          name: 'ensure_startup_launch_configuration_at_boot',
          level: 900,
        );
        return false;
      },
    );
  }

  Future<void> _persistUserDisabledStartup() async {
    if (!_repository.startWithWindows) {
      return;
    }

    developer.log(
      'Startup Apps disabled the entry; persisting startWithWindows=false without repairing',
      name: 'ensure_startup_launch_configuration_at_boot',
      level: 800,
    );
    final persistResult = await _repository.persistStartWithWindows(false);
    persistResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'Failed to persist startWithWindows=false after Startup Apps disable: $failure',
          name: 'ensure_startup_launch_configuration_at_boot',
          level: 900,
        );
      },
    );
  }

  Future<bool> _readSystemEnabled() async {
    final result = await _repository.readSystemStartupEnabled();
    return result.fold(
      (enabled) => enabled,
      (failure) {
        developer.log(
          'Failed to read system startup status at boot: $failure',
          name: 'ensure_startup_launch_configuration_at_boot',
          level: 900,
        );
        return false;
      },
    );
  }
}
