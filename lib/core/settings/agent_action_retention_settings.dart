import 'dart:math' as math;

import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Effective retention windows for agent action history, remote audit and captured output.
///
/// Persisted values in [IAppSettingsStore] override environment defaults for this process.
class AgentActionRetentionSettings {
  AgentActionRetentionSettings(this._store);

  static const String executionRetentionDaysKey = 'agent_action_execution_retention_days';
  static const String remoteAuditRetentionDaysKey = 'agent_action_remote_audit_retention_days';
  static const String capturedOutputRetentionHoursKey = 'agent_action_captured_output_retention_hours';

  static const int defaultExecutionRetentionDays = 3;
  static const int defaultRemoteAuditRetentionDays = 90;
  static const int defaultCapturedOutputRetentionHours = 24;

  static const int minExecutionRetentionDays = 1;
  static const int maxExecutionRetentionDays = 3650;
  static const int minRemoteAuditRetentionDays = 7;
  static const int maxRemoteAuditRetentionDays = 3650;
  static const int minCapturedOutputRetentionHours = 1;
  static const int maxCapturedOutputRetentionHours = 720;

  final IAppSettingsStore _store;

  int get executionRetentionDays => _storedInt(executionRetentionDaysKey) ?? _executionDaysFromEnv();

  int get remoteAuditRetentionDays => _storedInt(remoteAuditRetentionDaysKey) ?? _remoteAuditDaysFromEnv();

  int get capturedOutputRetentionHours {
    final stored = _storedInt(capturedOutputRetentionHoursKey);
    final hours = stored ?? _capturedOutputHoursFromEnv();
    return _clampCapturedOutputHours(hours, executionRetentionDays);
  }

  Duration get executionRetention => Duration(days: executionRetentionDays);

  Duration get remoteAuditRetention => Duration(days: remoteAuditRetentionDays);

  Duration get capturedOutputRetention => Duration(hours: capturedOutputRetentionHours);

  Duration get agentActionRpcIdempotencyTtl {
    final retentionSeconds = executionRetention.inSeconds;
    final defaultSeconds = retentionSeconds > 86400 ? 86400 : retentionSeconds;
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS') ?? '');
    if (parsed == null || parsed <= 0) {
      return Duration(seconds: defaultSeconds);
    }
    final clamped = parsed < 60 ? 60 : parsed;
    final effectiveSeconds = clamped > retentionSeconds ? retentionSeconds : clamped;
    return Duration(seconds: effectiveSeconds);
  }

  bool get hasPersistedOverrides =>
      _store.getInt(executionRetentionDaysKey) != null ||
      _store.getInt(remoteAuditRetentionDaysKey) != null ||
      _store.getInt(capturedOutputRetentionHoursKey) != null;

  Future<void> save({
    required int executionDays,
    required int remoteAuditDays,
    required int capturedOutputHours,
  }) async {
    final normalizedExecution = _clamp(executionDays, minExecutionRetentionDays, maxExecutionRetentionDays);
    final normalizedAudit = _clamp(remoteAuditDays, minRemoteAuditRetentionDays, maxRemoteAuditRetentionDays);
    final normalizedCaptured = _clampCapturedOutputHours(capturedOutputHours, normalizedExecution);

    await _store.setInt(executionRetentionDaysKey, normalizedExecution);
    await _store.setInt(remoteAuditRetentionDaysKey, normalizedAudit);
    await _store.setInt(capturedOutputRetentionHoursKey, normalizedCaptured);
    await _store.flushPendingPersistence();
  }

  Future<void> clearPersistedOverrides() async {
    await _store.remove(executionRetentionDaysKey);
    await _store.remove(remoteAuditRetentionDaysKey);
    await _store.remove(capturedOutputRetentionHoursKey);
    await _store.flushPendingPersistence();
  }

  int? _storedInt(String key) {
    final value = _store.getInt(key);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  static int _executionDaysFromEnv() {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_EXECUTION_RETENTION_DAYS') ?? '');
    if (parsed == null || parsed <= 0) {
      return defaultExecutionRetentionDays;
    }
    return _clamp(parsed, minExecutionRetentionDays, maxExecutionRetentionDays);
  }

  static int _remoteAuditDaysFromEnv() {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS') ?? '');
    if (parsed == null || parsed <= 0) {
      return defaultRemoteAuditRetentionDays;
    }
    return _clamp(parsed, minRemoteAuditRetentionDays, maxRemoteAuditRetentionDays);
  }

  static int _capturedOutputHoursFromEnv() {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS') ?? '');
    final hours = (parsed == null || parsed <= 0) ? defaultCapturedOutputRetentionHours : parsed;
    return _clampCapturedOutputHours(hours, _executionDaysFromEnv());
  }

  static int _clampCapturedOutputHours(int hours, int executionDays) {
    final maxHours = math.min(maxCapturedOutputRetentionHours, executionDays * 24);
    return _clamp(hours, minCapturedOutputRetentionHours, maxHours);
  }

  static String? _optionalEnv(String key) => AppEnvironment.get(key);

  static int _clamp(int value, int min, int max) => value < min ? min : value > max ? max : value;
}
