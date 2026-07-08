import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';

class StartupLaunchConfigurationMapper {
  const StartupLaunchConfigurationMapper._();

  static Future<StartupLaunchConfigurationOutcome?> validate(
    IStartupPreferencesRepository repository, {
    bool allowElevation = true,
  }) async {
    try {
      final result = await repository.ensureLaunchConfiguration(
        allowElevation: allowElevation,
      );
      return result.fold(
        fromStatus,
        fromFailure,
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Startup launch configuration validation threw',
        name: 'startup_launch_configuration_mapper',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const StartupLaunchConfigurationOutcome(
        StartupLaunchConfigurationOutcomeType.repairFailed,
      );
    }
  }

  static StartupLaunchConfigurationOutcome? fromStatus(
    StartupLaunchConfigurationStatus status,
  ) {
    return switch (status) {
      StartupLaunchConfigurationStatus.unchanged => null,
      StartupLaunchConfigurationStatus.repaired => const StartupLaunchConfigurationOutcome(
        StartupLaunchConfigurationOutcomeType.repaired,
      ),
      StartupLaunchConfigurationStatus.needsRepair => const StartupLaunchConfigurationOutcome(
        StartupLaunchConfigurationOutcomeType.needsRepair,
      ),
      StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry => const StartupLaunchConfigurationOutcome(
        StartupLaunchConfigurationOutcomeType.repairedWithLegacyEntry,
      ),
    };
  }

  static StartupLaunchConfigurationOutcome fromFailure(Object failure) {
    developer.log(
      'Startup launch configuration failed: $failure',
      name: 'startup_launch_configuration_mapper',
      level: 900,
    );
    if (failure is StartupServiceFailure) {
      return StartupLaunchConfigurationOutcome(
        StartupLaunchConfigurationOutcomeType.repairFailed,
        startupFailureCode: failure.startupCode,
      );
    }
    return const StartupLaunchConfigurationOutcome(
      StartupLaunchConfigurationOutcomeType.repairFailed,
    );
  }
}
