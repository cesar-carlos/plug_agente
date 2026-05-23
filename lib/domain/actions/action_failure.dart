import 'package:plug_agente/domain/errors/failures.dart';

class ActionFailure extends Failure {
  ActionFailure(String message) : super(message, 'ACTION_ERROR');

  ActionFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(defaultCode: 'ACTION_ERROR');

  @override
  bool get isRecoverable => true;
}

class ActionValidationFailure extends ActionFailure {
  ActionValidationFailure(super.message);

  ActionValidationFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_VALIDATION_ERROR');
}

class ActionQueueFailure extends ActionFailure {
  ActionQueueFailure(super.message);

  ActionQueueFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_QUEUE_ERROR');
}

class ActionAuthorizationFailure extends ActionFailure {
  ActionAuthorizationFailure(super.message);

  ActionAuthorizationFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_AUTHORIZATION_ERROR');
}

class ActionRuntimeFailure extends ActionFailure {
  ActionRuntimeFailure(super.message);

  ActionRuntimeFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_RUNTIME_ERROR');
}

class ActionTimeoutFailure extends ActionRuntimeFailure {
  ActionTimeoutFailure(super.message);

  ActionTimeoutFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_TIMEOUT');

  @override
  bool get isTransient => true;
}

class ActionNotFoundFailure extends ActionFailure {
  ActionNotFoundFailure(super.message);

  ActionNotFoundFailure.withContext({
    required super.message,
    String? code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(code: code ?? 'ACTION_NOT_FOUND');
}

/// Stable [Failure.code] values for agent action flows.
abstract final class AgentActionFailureCode {
  static const alreadyFinished = 'ACTION_ALREADY_FINISHED';
  static const appCloseElevatedActionBlocked = 'ACTION_APP_CLOSE_ELEVATED_ACTION_BLOCKED';
  static const appCloseRemoteActionBlocked = 'ACTION_APP_CLOSE_REMOTE_ACTION_BLOCKED';
  static const appCloseRuntimeTooLong = 'ACTION_APP_CLOSE_RUNTIME_TOO_LONG';
  static const cancelNotRunning = 'ACTION_CANCEL_NOT_RUNNING';
  static const contextPathNotFound = 'ACTION_CONTEXT_PATH_NOT_FOUND';
  static const environmentProfileDenied = 'ACTION_ENVIRONMENT_PROFILE_DENIED';
  static const executableNotFound = 'ACTION_EXECUTABLE_NOT_FOUND';
  static const executionCancelled = 'ACTION_CANCELLED';
  static const executionKilled = 'ACTION_KILLED';
  static const executionTimedOut = 'ACTION_TIMEOUT';
  static const exitCodeRejected = 'ACTION_EXIT_CODE_REJECTED';
  static const featureDisabled = 'ACTION_FEATURE_DISABLED';
  static const interruptedOnBootstrap = 'ACTION_INTERRUPTED_ON_BOOTSTRAP';
  static const interpreterNotFound = 'ACTION_INTERPRETER_NOT_FOUND';
  static const javaNotFound = 'ACTION_JAVA_NOT_FOUND';
  static const killFailed = 'ACTION_KILL_FAILED';
  static const killPermissionDenied = 'ACTION_KILL_PERMISSION_DENIED';
  static const lifecycleTriggerTimeout = 'ACTION_LIFECYCLE_TRIGGER_TIMEOUT';
  static const maintenanceMode = 'ACTION_MAINTENANCE_MODE';
  static const pathNotFound = 'ACTION_PATH_NOT_FOUND';
  static const pathPermissionDenied = 'ACTION_PATH_PERMISSION_DENIED';
  static const pathSnapshotMismatch = 'ACTION_PATH_SNAPSHOT_MISMATCH';
  static const preflightRequiredForActive = 'ACTION_PREFLIGHT_REQUIRED_FOR_ACTIVE';
  static const preflightExpiredForActive = 'ACTION_PREFLIGHT_EXPIRED_FOR_ACTIVE';
  static const processIdMismatch = 'ACTION_PROCESS_ID_MISMATCH';
  static const processIdentityMismatch = 'ACTION_PROCESS_IDENTITY_MISMATCH';
  static const processIdentityUnavailable = 'ACTION_PROCESS_IDENTITY_UNAVAILABLE';
  static const processNotActive = 'ACTION_PROCESS_NOT_ACTIVE';
  static const queueCancelled = 'ACTION_QUEUE_CANCELLED';
  static const queueConcurrencyRejected = 'ACTION_QUEUE_CONCURRENCY_REJECTED';
  static const queueFull = 'ACTION_QUEUE_FULL';
  static const queueIgnored = 'ACTION_QUEUE_IGNORED';
  static const queueItemNotFound = 'ACTION_QUEUE_ITEM_NOT_FOUND';
  static const queueLimitReached = 'ACTION_QUEUE_LIMIT_REACHED';
  static const queueTimeout = 'ACTION_QUEUE_TIMEOUT';
  static const remoteApprovalAppCloseConflict = 'ACTION_REMOTE_APPROVAL_APP_CLOSE_CONFLICT';
  static const remoteFeatureDisabled = 'ACTION_REMOTE_FEATURE_DISABLED';
  static const remoteAdHocDisabled = 'ACTION_REMOTE_AD_HOC_DISABLED';
  static const elevatedDisabled = 'ACTION_ELEVATED_DISABLED';
  static const elevatedNotConfigured = 'ACTION_ELEVATED_NOT_CONFIGURED';
  static const elevatedRunnerDegraded = 'ACTION_ELEVATED_RUNNER_DEGRADED';
  static const elevatedRequestProtectionFailed = 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED';
  static const elevatedSubmitFailed = 'ACTION_ELEVATED_SUBMIT_FAILED';
  static const unsupportedForElevatedRunner = 'ACTION_UNSUPPORTED_FOR_ELEVATED_RUNNER';
  static const schedulerBootstrapFailed = 'ACTION_SCHEDULER_BOOTSTRAP_FAILED';
  static const remoteIdempotencyRequired = 'ACTION_REMOTE_IDEMPOTENCY_REQUIRED';
  static const remoteTriggerRequired = 'ACTION_REMOTE_TRIGGER_REQUIRED';
  static const remoteTriggerAmbiguous = 'ACTION_REMOTE_TRIGGER_AMBIGUOUS';
  static const remoteTriggerInvalid = 'ACTION_REMOTE_TRIGGER_INVALID';
  static const remoteContextNotSupported = 'ACTION_REMOTE_CONTEXT_NOT_SUPPORTED';
  static const remoteNotApproved = 'ACTION_REMOTE_NOT_APPROVED';
  static const runnerMissing = 'ACTION_RUNNER_MISSING';
  static const secretUnavailable = 'ACTION_SECRET_UNAVAILABLE';
  static const runtimeError = 'ACTION_RUNTIME_ERROR';
  static const runtimeUnknown = 'ACTION_RUNTIME_UNKNOWN';
  static const subsystemDegraded = 'ACTION_SUBSYSTEM_DEGRADED';
  static const subsystemDraining = 'ACTION_SUBSYSTEM_DRAINING';
  static const subsystemReady = 'ACTION_SUBSYSTEM_READY';
  static const subsystemStarting = 'ACTION_SUBSYSTEM_STARTING';
  static const triggerActionIdBlank = 'ACTION_TRIGGER_ACTION_ID_BLANK';
  static const workingDirectoryNotFound = 'ACTION_WORKING_DIRECTORY_NOT_FOUND';
}
