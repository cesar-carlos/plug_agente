import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class SyncStartupStatus {
  SyncStartupStatus(this._repository);

  final IStartupPreferencesRepository _repository;

  Future<Result<SyncStartupStatusOutcome>> call() async {
    if (!_repository.isStartupServiceAvailable) {
      return const Success(SyncStartupStatusOutcome());
    }

    final enabledResult = await _repository.readSystemStartupEnabled();
    return enabledResult.fold(
      (isEnabled) async {
        bool? reconciled;
        final stored = _repository.startWithWindows;
        if (isEnabled != stored) {
          developer.log(
            'Startup status out of sync (system: $isEnabled, settings: $stored), updating settings',
            name: 'sync_startup_status',
            level: 800,
          );
          reconciled = isEnabled;
          final persistResult = await _repository.persistStartWithWindows(isEnabled);
          persistResult.fold(
            (_) {},
            (failure) {
              developer.log(
                'Failed to persist reconciled startup status: $failure',
                name: 'sync_startup_status',
                level: 900,
              );
            },
          );
        }

        StartupLaunchConfigurationOutcome? launchConfiguration;
        if (isEnabled) {
          launchConfiguration = await StartupLaunchConfigurationMapper.validate(
            _repository,
            allowElevation: false,
          );
        }

        return Success(
          SyncStartupStatusOutcome(
            reconciledStartWithWindows: reconciled,
            launchConfiguration: launchConfiguration,
          ),
        );
      },
      Failure.new,
    );
  }
}
