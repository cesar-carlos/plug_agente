import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';

/// What the boot auto-start step observed, kept for the startup diagnostic.
class StartupBootDiagnostics {
  const StartupBootDiagnostics({
    required this.isAutostartLaunch,
    required this.launchConfigurationValidated,
    this.launchConfiguration,
  });

  final bool isAutostartLaunch;

  /// False when boot skipped validation (auto-start off, disabled by the user
  /// in Startup Apps, or startup service unavailable).
  final bool launchConfigurationValidated;

  /// Null when validation ran and left the configuration unchanged.
  final StartupLaunchConfigurationOutcome? launchConfiguration;
}

/// Process-scoped cache so cold-start sync can reuse the boot ensure outcome
/// and avoid a second registry repair pass.
class StartupConfigurationSessionState {
  bool _hasBootOutcome = false;
  StartupLaunchConfigurationOutcome? _bootLaunchConfiguration;
  StartupBootDiagnostics? _bootDiagnostics;

  /// Unlike [takeBootLaunchConfiguration], this survives reads so the
  /// diagnostic can be copied at any time during the session.
  StartupBootDiagnostics? get bootDiagnostics => _bootDiagnostics;

  void recordBootDiagnostics(StartupBootDiagnostics diagnostics) {
    _bootDiagnostics = diagnostics;
  }

  void setBootLaunchConfiguration(StartupLaunchConfigurationOutcome? outcome) {
    _hasBootOutcome = true;
    _bootLaunchConfiguration = outcome;
  }

  /// Returns the boot outcome once, then clears the cache.
  ///
  /// When `present` is false, no boot outcome was stored. When `present` is
  /// true, `outcome` may still be null (unchanged / no notice).
  ({bool present, StartupLaunchConfigurationOutcome? outcome}) takeBootLaunchConfiguration() {
    if (!_hasBootOutcome) {
      return (present: false, outcome: null);
    }
    final outcome = _bootLaunchConfiguration;
    _hasBootOutcome = false;
    _bootLaunchConfiguration = null;
    return (present: true, outcome: outcome);
  }
}
