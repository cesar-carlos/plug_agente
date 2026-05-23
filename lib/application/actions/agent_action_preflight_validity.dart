import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';

/// Evaluates whether a recorded preflight still matches definition content and TTL.
abstract final class AgentActionPreflightValidity {
  static Duration validityDuration({AgentActionPreflightSettings? settings}) {
    return settings?.validityDuration ?? AgentActionPolicyDefaults.preflightValidityDuration;
  }

  static DateTime? expiresAt(
    DateTime? lastValidatedAt, {
    AgentActionPreflightSettings? settings,
  }) {
    if (lastValidatedAt == null) {
      return null;
    }

    return lastValidatedAt.toUtc().add(validityDuration(settings: settings));
  }

  static bool isTimestampValid(
    DateTime? lastValidatedAt, {
    required DateTime now,
    AgentActionPreflightSettings? settings,
  }) {
    final expiry = expiresAt(lastValidatedAt, settings: settings);
    if (expiry == null) {
      return false;
    }

    return !now.toUtc().isAfter(expiry);
  }

  static bool isValid({
    required String? recordedHash,
    required String expectedHash,
    required DateTime? lastValidatedAt,
    required DateTime now,
    AgentActionPreflightSettings? settings,
  }) {
    if (recordedHash == null || recordedHash.isEmpty) {
      return false;
    }
    if (recordedHash != expectedHash) {
      return false;
    }

    return isTimestampValid(lastValidatedAt, now: now, settings: settings);
  }
}
