import 'dart:developer' as developer;
import 'dart:math';

import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';

/// Resolves and persists the rollout bucket used for silent update eligibility.
class SilentUpdateRolloutBucketResolver {
  SilentUpdateRolloutBucketResolver({
    IUpdatePreferencesRepository? preferences,
  }) : _preferences = preferences;

  final IUpdatePreferencesRepository? _preferences;

  Future<int> resolve() async {
    final existing = _preferences?.readRolloutBucket();
    if (existing != null && existing >= 0 && existing < 100) return existing;
    final generated = Random.secure().nextInt(100);
    final preferences = _preferences;
    if (preferences != null) {
      try {
        await preferences.writeRolloutBucket(generated);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to persist rollout bucket; using in-memory value for this check',
          name: 'silent_update_coordinator',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return generated;
  }
}
