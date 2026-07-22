import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';

/// Process-scoped cache so cold-start sync can reuse the boot ensure outcome
/// and avoid a second registry repair pass.
class StartupConfigurationSessionState {
  bool _hasBootOutcome = false;
  StartupLaunchConfigurationOutcome? _bootLaunchConfiguration;

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
