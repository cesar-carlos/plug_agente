/// Stable `failure.context['reason']` for agent action triggers and related lifecycle validation.
abstract final class AgentActionTriggerConstants {
  static const String blankActionIdReason = 'blank_action_id';

  static const String nonTemporalTriggerReason = 'non_temporal_trigger';

  static const String triggerDisabledReason = 'trigger_disabled';

  static const String remoteTriggerRequiredReason = 'remote_trigger_required';

  static const String remoteTriggerAmbiguousReason = 'remote_trigger_ambiguous';

  static const String remoteTriggerActionMismatchReason = 'remote_trigger_action_mismatch';

  static const String remoteTriggerTypeMismatchReason = 'remote_trigger_type_mismatch';

  static const String lifecycleTriggerTimeoutReason = 'lifecycle_trigger_timeout';

  static const String appCloseRuntimeTooLongReason = 'app_close_runtime_too_long';

  static const String appCloseElevatedActionBlockedReason = 'app_close_elevated_action_blocked';

  static const String appCloseRemoteActionBlockedReason = 'app_close_remote_action_blocked';

  static const String remoteApprovalAppCloseConflictReason = 'remote_approval_app_close_conflict';

  static const String timezoneNotSupportedForTriggerTypeReason = 'timezone_not_supported_for_trigger_type';

  static const String unknownTimezoneReason = 'unknown_timezone';

  static const String requiredForOnceReason = 'required_for_once';

  static const String requiredForIntervalReason = 'required_for_interval';

  static const String invalidWeekdaysReason = 'invalid_weekdays';

  static const String invalidDayOfMonthReason = 'invalid_day_of_month';

  static const String scheduleNotSupportedReason = 'schedule_not_supported';

  static const String endBeforeStartReason = 'end_before_start';

  static const String invalidTimeOfDayReason = 'invalid_time_of_day';

  static const String schedulerBootstrapFailedReason = 'scheduler_bootstrap_failed';

  static const String schedulerInstanceLockedReason = 'scheduler_instance_locked';

  static const String schedulerStorageAccessDeniedReason = 'scheduler_storage_access_denied';
}
