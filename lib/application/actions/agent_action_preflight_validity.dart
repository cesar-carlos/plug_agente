import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';

/// Evaluates whether a recorded preflight still matches definition content and TTL.
abstract final class AgentActionPreflightValidity {
  static Duration get validityDuration => AgentActionPolicyDefaults.preflightValidityDuration;

  static DateTime? expiresAt(DateTime? lastValidatedAt) {
    if (lastValidatedAt == null) {
      return null;
    }

    return lastValidatedAt.toUtc().add(validityDuration);
  }

  static bool isTimestampValid(
    DateTime? lastValidatedAt, {
    required DateTime now,
  }) {
    final expiry = expiresAt(lastValidatedAt);
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
  }) {
    if (recordedHash == null || recordedHash.isEmpty) {
      return false;
    }
    if (recordedHash != expectedHash) {
      return false;
    }

    return isTimestampValid(lastValidatedAt, now: now);
  }
}
