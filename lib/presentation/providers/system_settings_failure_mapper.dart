import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';

class SystemSettingsFailureMapper {
  const SystemSettingsFailureMapper._();

  static SystemSettingsErrorState startupFailure(Object failure) {
    if (failure is StartupServiceFailure) {
      developer.log(
        failure.message,
        name: 'system_settings_failure_mapper',
        level: 900,
      );
      return SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupToggleFailed,
        startupFailureCode: failure.code,
      );
    }
    return const SystemSettingsErrorState(
      code: SystemSettingsErrorCode.startupToggleFailed,
    );
  }

  static SystemSettingsErrorState preferenceFailure(Object failure) {
    final detail = failure is domain.Failure && failure.cause != null ? failure.cause.toString() : failure.toString();
    return SystemSettingsErrorState(
      code: SystemSettingsErrorCode.settingsPersistenceFailed,
      detail: detail,
    );
  }

  static SystemSettingsErrorState openSystemSettingsFailure(Object failure) {
    return SystemSettingsErrorState(
      code: SystemSettingsErrorCode.startupOpenSystemSettingsFailed,
      startupFailureCode: failure is StartupServiceFailure ? failure.code : null,
    );
  }

  static SystemSettingsNoticeState? noticeFromLaunchOutcome(
    StartupLaunchConfigurationOutcome? outcome,
  ) {
    if (outcome == null || !outcome.hasNotice) {
      return null;
    }

    return SystemSettingsNoticeState(
      code: switch (outcome.type) {
        StartupLaunchConfigurationOutcomeType.repaired => SystemSettingsNoticeCode.startupLaunchConfigurationRepaired,
        StartupLaunchConfigurationOutcomeType.repairFailed =>
          SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed,
        StartupLaunchConfigurationOutcomeType.needsRepair =>
          SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed,
        StartupLaunchConfigurationOutcomeType.repairedWithLegacyEntry =>
          SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry,
        StartupLaunchConfigurationOutcomeType.none => SystemSettingsNoticeCode.startupLaunchConfigurationReady,
      },
      startupFailureCode: outcome.startupFailureCode,
    );
  }
}
