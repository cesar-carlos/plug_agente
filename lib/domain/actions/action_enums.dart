enum AgentActionType {
  commandLine,
  executable,
  script,
  jar,
  email,
  comObject,
  developer,
}

enum AgentActionState {
  active,
  paused,
  disabled,
  needsValidation,
}

enum AgentActionTriggerType {
  manual,
  remote,
  once,
  interval,
  daily,
  weekly,
  monthly,
  appStart,
  appClose,
}

enum AgentActionExecutionStatus {
  queued,
  running,
  succeeded,
  failed,
  skipped,
  cancelled,
  killed,
  timedOut,
  interrupted,
  unknown,
}

enum AgentActionSubsystemStatus {
  starting,
  ready,
  draining,
  maintenance,
  degraded,
  disabled,
}

enum AgentActionConcurrencyBehavior {
  allowParallel,
  enqueue,
  reject,
  ignore,
}

enum AgentActionOnAppExitBehavior {
  killMainProcess,
  waitThenKillMainProcess,
  leaveRunning,
}

/// How the child process console/window should be created on desktop hosts.
enum AgentActionProcessWindowMode {
  normal,
  hidden,
  minimized,
}

enum AgentActionContextInjectionMode {
  argument,
  file,
  environment,
  stdin,
}

/// How captured child-process streams are decoded before redaction and persistence.
enum AgentActionOutputEncodingMode {
  utf8,
  systemConsole,
}

enum AgentActionDeveloperEngine {
  data7Executor,
}

enum AgentActionRequestSource {
  localUi,
  scheduler,
  remoteHub,
  appLifecycle,
}

/// How execution preflight treats path or content drift since definition validation.
enum AgentActionPathChangePolicy {
  allowChanged,
  warnIfChanged,
  failIfChanged,
}

extension AgentActionExecutionStatusX on AgentActionExecutionStatus {
  bool get isTerminal {
    return switch (this) {
      AgentActionExecutionStatus.succeeded ||
      AgentActionExecutionStatus.failed ||
      AgentActionExecutionStatus.skipped ||
      AgentActionExecutionStatus.cancelled ||
      AgentActionExecutionStatus.killed ||
      AgentActionExecutionStatus.timedOut ||
      AgentActionExecutionStatus.interrupted ||
      AgentActionExecutionStatus.unknown => true,
      AgentActionExecutionStatus.queued || AgentActionExecutionStatus.running => false,
    };
  }

  bool get isSuccess => this == AgentActionExecutionStatus.succeeded;
}
