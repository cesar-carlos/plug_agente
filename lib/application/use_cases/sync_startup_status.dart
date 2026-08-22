import 'dart:developer' as developer;

import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class SyncStartupStatus {
  SyncStartupStatus(
    this._repository, {
    StartupConfigurationSessionState? sessionState,
  }) : _sessionState = sessionState;

  final IStartupPreferencesRepository _repository;
  final StartupConfigurationSessionState? _sessionState;

  Future<Result<SyncStartupStatusOutcome>> call({
    bool Function()? shouldAbort,
  }) async {
    if (!_repository.isStartupServiceAvailable) {
      return const Success(SyncStartupStatusOutcome());
    }

    final enabledResult = await _repository.readSystemStartupEnabled();
    return enabledResult.fold(
      (isEnabled) async {
        if (shouldAbort?.call() ?? false) {
          return const Success(SyncStartupStatusOutcome());
        }

        final stored = _repository.startWithWindows;
        StartupLaunchConfigurationOutcome? launchConfiguration;

        final userDisabled = await _readUserDisabledStartup();
        if (userDisabled) {
          if (shouldAbort?.call() ?? false) {
            return const Success(SyncStartupStatusOutcome());
          }
          return _reconcileUserDisabledStartup(stored: stored);
        }

        final bootCache = _sessionState?.takeBootLaunchConfiguration();
        if (bootCache != null && bootCache.present) {
          launchConfiguration = bootCache.outcome;
        } else if (isEnabled || stored) {
          launchConfiguration = await StartupLaunchConfigurationMapper.validate(
            _repository,
            allowElevation: false,
          );
        }

        final launchConfigurationType = launchConfiguration?.type;
        // ensure may have just created/repaired HKCU; treat that as enabled for
        // reconcile even though the pre-ensure isEnabled snapshot was false.
        final repairedNow =
            launchConfigurationType == StartupLaunchConfigurationOutcomeType.repaired ||
            launchConfigurationType == StartupLaunchConfigurationOutcomeType.repairedWithLegacyEntry;
        final effectiveSystemEnabled = isEnabled || repairedNow;

        // `needsRepair` means the entry exists but is broken; `repairFailed`
        // means validation itself failed. Either way the real state is not
        // "user disabled startup", so the stored preference must survive
        // until a repair (or an explicit toggle) resolves it.
        final hasRepairableStoredEntry =
            stored &&
            !effectiveSystemEnabled &&
            (launchConfigurationType == StartupLaunchConfigurationOutcomeType.needsRepair ||
                launchConfigurationType == StartupLaunchConfigurationOutcomeType.repairFailed);
        bool? reconciled;
        if (effectiveSystemEnabled != stored && !hasRepairableStoredEntry) {
          if (shouldAbort?.call() ?? false) {
            return const Success(SyncStartupStatusOutcome());
          }
          developer.log(
            'Startup status out of sync (system: $effectiveSystemEnabled, settings: $stored), updating settings',
            name: 'sync_startup_status',
            level: 800,
          );
          reconciled = effectiveSystemEnabled;
          final persistResult = await _repository.persistStartWithWindows(effectiveSystemEnabled);
          final persistFailure = persistResult.fold(
            (_) => null,
            (failure) => failure,
          );
          if (persistFailure != null) {
            developer.log(
              'Failed to persist reconciled startup status: $persistFailure',
              name: 'sync_startup_status',
              level: 900,
            );
            return Failure(persistFailure);
          }
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

  Future<bool> _readUserDisabledStartup() async {
    final result = await _repository.readStartupDisabledByUser();
    return result.fold(
      (disabled) => disabled,
      (failure) {
        developer.log(
          'Failed to read Startup Apps disable state during sync: $failure',
          name: 'sync_startup_status',
          level: 900,
        );
        return false;
      },
    );
  }

  Future<Result<SyncStartupStatusOutcome>> _reconcileUserDisabledStartup({
    required bool stored,
  }) async {
    if (!stored) {
      return const Success(SyncStartupStatusOutcome());
    }

    developer.log(
      'Startup Apps disabled the entry; persisting startWithWindows=false without repairing',
      name: 'sync_startup_status',
      level: 800,
    );
    final persistResult = await _repository.persistStartWithWindows(false);
    final persistFailure = persistResult.fold(
      (_) => null,
      (failure) => failure,
    );
    if (persistFailure != null) {
      developer.log(
        'Failed to persist startWithWindows=false after Startup Apps disable: $persistFailure',
        name: 'sync_startup_status',
        level: 900,
      );
      return Failure(persistFailure);
    }

    return const Success(
      SyncStartupStatusOutcome(reconciledStartWithWindows: false),
    );
  }
}
