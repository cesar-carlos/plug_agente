import 'package:plug_agente/domain/errors/startup_service_failure.dart';

enum StartupChangeOutcome {
  enabled,
  disabled,
}

enum StartupLaunchConfigurationOutcomeType {
  none,
  repaired,
  repairFailed,
  needsRepair,
  repairedWithLegacyEntry,
}

class StartupLaunchConfigurationOutcome {
  const StartupLaunchConfigurationOutcome(
    this.type, {
    this.startupFailureCode,
  });

  final StartupLaunchConfigurationOutcomeType type;
  final StartupServiceFailureCode? startupFailureCode;

  bool get hasNotice => type != StartupLaunchConfigurationOutcomeType.none;
}

class SyncStartupStatusOutcome {
  const SyncStartupStatusOutcome({
    this.reconciledStartWithWindows,
    this.launchConfiguration,
  });

  final bool? reconciledStartWithWindows;
  final StartupLaunchConfigurationOutcome? launchConfiguration;
}

class SetStartWithWindowsOutcome {
  const SetStartWithWindowsOutcome({
    required this.change,
    this.launchConfiguration,
  });

  final StartupChangeOutcome change;
  final StartupLaunchConfigurationOutcome? launchConfiguration;
}

enum TrayBehaviorKind {
  minimizeToTray,
  closeToTray,
}
