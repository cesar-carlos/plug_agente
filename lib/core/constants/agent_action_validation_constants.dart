/// Stable `failure.context['reason']` for agent action validation and preflight checks.
abstract final class AgentActionValidationConstants {
  static const String fieldRequiredReason = 'required';

  static const String blankValueReason = 'blank_value';

  static const String blankFilterReason = 'blank_filter';

  static const String invalidVersionReason = 'invalid_version';

  static const String invalidQueuePolicyReason = 'invalid_queue_policy';

  static const String policyDeploymentCeilingExceededReason = 'policy_deployment_ceiling_exceeded';

  static const String invalidTimeoutPolicyReason = 'invalid_timeout_policy';

  static const String elevatedRetryNotAllowedReason = 'elevated_retry_not_allowed';

  static const String invalidPathPolicyReason = 'invalid_path_policy';

  static const String invalidContextJsonSchemaDefinitionReason = 'invalid_context_json_schema_definition';

  static const String invalidRuntimeParameterSchemaDefinitionReason = 'invalid_runtime_parameter_schema_definition';

  static const String runtimeParametersSchemaMismatchReason = 'runtime_parameters_schema_mismatch';

  static const String contextInjectionRequiresFileReason = 'context_injection_requires_file';

  static const String contextInjectionRejectsFileReason = 'context_injection_rejects_file';

  static const String contextInjectionRequiresStdinPayloadReason = 'context_injection_requires_stdin_payload';

  static const String invalidEnvironmentVariableNameReason = 'invalid_environment_variable_name';

  static const String environmentVariableNotAllowedReason = 'environment_variable_not_allowed';

  static const String invalidEnvironmentVariableValueReason = 'invalid_environment_variable_value';

  static const String invalidContextPathReason = 'invalid_context_path';

  static const String invalidRuntimeParametersReason = 'invalid_runtime_parameters';

  static const String invalidIdempotencyKeyReason = 'invalid_idempotency_key';

  static const String invalidRequestedByReason = 'invalid_requested_by';

  static const String invalidTraceIdReason = 'invalid_trace_id';

  static const String invalidTriggerIdReason = 'invalid_trigger_id';

  static const String invalidSecretNameReason = 'invalid_secret_name';

  static const String secretValueRequiredReason = 'secret_value_required';

  static const String secretStoreUnavailableReason = 'secret_store_unavailable';

  static const String secretPersistFailedReason = 'secret_persist_failed';
}
