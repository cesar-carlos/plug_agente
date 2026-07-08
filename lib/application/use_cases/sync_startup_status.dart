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
        final stored = _repository.startWithWindows;
        StartupLaunchConfigurationOutcome? launchConfiguration;
        if (isEnabled || stored) {
          launchConfiguration = await StartupLaunchConfigurationMapper.validate(
            _repository,
            allowElevation: false,
          );
        }

        // `needsRepair` means the entry exists but is broken; `repairFailed`
        // means validation itself failed. Either way the real state is not
        // "user disabled startup", so the stored preference must survive
        // until a repair (or an explicit toggle) resolves it.
        final launchConfigurationType = launchConfiguration?.type;
        final hasRepairableStoredEntry =
            stored &&
            !isEnabled &&
            (launchConfigurationType == StartupLaunchConfigurationOutcomeType.needsRepair ||
                launchConfigurationType == StartupLaunchConfigurationOutcomeType.repairFailed);
        bool? reconciled;
        if (isEnabled != stored && !hasRepairableStoredEntry) {
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
        } else if (hasRepairableStoredEntry) {
          developer.log(
            'Startup entry needs repair; preserving stored startup preference until repair completes',
            name: 'sync_startup_status',
            level: 800,
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
