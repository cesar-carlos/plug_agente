import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';

/// Resolves hub persistent retry tuning: persisted overrides, then `.env`, then
/// built-in defaults from `ConnectionConstants`.
class HubResilienceConfig {
  HubResilienceConfig(this._flags);

  final FeatureFlags _flags;

  static const String envMaxFailedTicksKey = 'HUB_PERSISTENT_RETRY_MAX_FAILED_TICKS';
  static const String envIntervalSecondsKey = 'HUB_PERSISTENT_RETRY_INTERVAL_SECONDS';

  static const int _maxFailedTicksUpperBound = 1 << 22;

  /// Effective max failed persistent reconnect ticks (`0` = unlimited).
  int get maxFailedTicks {
    final fromFlag = _flags.hubPersistentRetryMaxFailedTicksOverride;
    if (fromFlag != null) {
      return fromFlag.clamp(0, _maxFailedTicksUpperBound);
    }
    final fromEnv = _readOptionalNonNegativeIntEnv(envMaxFailedTicksKey);
    if (fromEnv != null) {
      return fromEnv.clamp(0, _maxFailedTicksUpperBound);
    }
    return ConnectionConstants.hubPersistentRetryMaxFailedTicks;
  }

  Duration get persistentRetryInterval {
    final fromFlag = _flags.hubPersistentRetryIntervalSecondsOverride;
    if (fromFlag != null) {
      final s = fromFlag.clamp(5, 86400);
      return Duration(seconds: s);
    }
    final fromEnv = _readOptionalPositiveIntEnv(envIntervalSecondsKey);
    if (fromEnv != null) {
      final s = fromEnv.clamp(5, 86400);
      return Duration(seconds: s);
    }
    return ConnectionConstants.hubPersistentRetryInterval;
  }

  static int? _readOptionalNonNegativeIntEnv(String key) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  static int? _readOptionalPositiveIntEnv(String key) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      return null;
    }
    return parsed;
  }
}
