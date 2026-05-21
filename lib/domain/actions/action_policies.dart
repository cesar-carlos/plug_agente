import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_execution.dart';

class AgentActionRemotePolicy {
  const AgentActionRemotePolicy({
    this.isEnabled = false,
    this.allowAdHoc = false,
    this.approvedBy,
    this.approvedAt,
    this.approvalReason,
    this.riskFingerprint,
    this.requiresReapproval = false,
  });

  final bool isEnabled;
  final bool allowAdHoc;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? approvalReason;
  final String? riskFingerprint;
  final bool requiresReapproval;

  bool get canRunSavedAction => isEnabled && approvedAt != null && !requiresReapproval;

  AgentActionRemotePolicy copyWith({
    bool? isEnabled,
    bool? allowAdHoc,
    String? approvedBy,
    DateTime? approvedAt,
    String? approvalReason,
    String? riskFingerprint,
    bool? requiresReapproval,
    bool clearApprovedBy = false,
    bool clearApprovedAt = false,
    bool clearApprovalReason = false,
    bool clearRiskFingerprint = false,
  }) {
    return AgentActionRemotePolicy(
      isEnabled: isEnabled ?? this.isEnabled,
      allowAdHoc: allowAdHoc ?? this.allowAdHoc,
      approvedBy: clearApprovedBy ? null : (approvedBy ?? this.approvedBy),
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      approvalReason: clearApprovalReason ? null : (approvalReason ?? this.approvalReason),
      riskFingerprint: clearRiskFingerprint ? null : (riskFingerprint ?? this.riskFingerprint),
      requiresReapproval: requiresReapproval ?? this.requiresReapproval,
    );
  }
}

class AgentActionQueuePolicy {
  const AgentActionQueuePolicy({
    this.maxConcurrent = 1,
    this.maxQueued = 100,
    this.queueTimeout = const Duration(minutes: 5),
    this.concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue,
  });

  final int maxConcurrent;
  final int maxQueued;
  final Duration queueTimeout;
  final AgentActionConcurrencyBehavior concurrencyBehavior;
}

class AgentActionTimeoutPolicy {
  const AgentActionTimeoutPolicy({
    this.maxRuntime = const Duration(minutes: 30),
    this.killMainProcessOnTimeout = true,
  });

  final Duration maxRuntime;
  final bool killMainProcessOnTimeout;

  AgentActionTimeoutPolicy copyWith({
    Duration? maxRuntime,
    bool? killMainProcessOnTimeout,
  }) {
    return AgentActionTimeoutPolicy(
      maxRuntime: maxRuntime ?? this.maxRuntime,
      killMainProcessOnTimeout: killMainProcessOnTimeout ?? this.killMainProcessOnTimeout,
    );
  }
}

class AgentActionCapturePolicy {
  const AgentActionCapturePolicy({
    this.captureStdout = true,
    this.captureStderr = true,
    this.maxCapturedOutputBytes = 64 * 1024,
    this.redactBeforePersisting = true,
  });

  final bool captureStdout;
  final bool captureStderr;
  final int maxCapturedOutputBytes;
  final bool redactBeforePersisting;
}

class AgentActionEncodingPolicy {
  const AgentActionEncodingPolicy({
    this.stdout = AgentActionOutputEncodingMode.systemConsole,
    this.stderr = AgentActionOutputEncodingMode.systemConsole,
  });

  final AgentActionOutputEncodingMode stdout;
  final AgentActionOutputEncodingMode stderr;

  AgentActionEncodingPolicy copyWith({
    AgentActionOutputEncodingMode? stdout,
    AgentActionOutputEncodingMode? stderr,
  }) {
    return AgentActionEncodingPolicy(
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
    );
  }
}

class AgentActionContextPolicy {
  const AgentActionContextPolicy({
    this.allowedContextExtensions = const {'.txt', '.json'},
    this.maxContextBytes = 256 * 1024,
    this.contextJsonSchema,
    this.runtimeParameterSchema,
    this.injectionMode = AgentActionContextInjectionMode.argument,
  });

  final Set<String> allowedContextExtensions;
  final int maxContextBytes;
  final Map<String, Object?>? contextJsonSchema;
  final Map<String, Object?>? runtimeParameterSchema;
  final AgentActionContextInjectionMode injectionMode;

  AgentActionContextPolicy copyWith({
    Set<String>? allowedContextExtensions,
    int? maxContextBytes,
    Map<String, Object?>? contextJsonSchema,
    Map<String, Object?>? runtimeParameterSchema,
    bool clearContextJsonSchema = false,
    bool clearRuntimeParameterSchema = false,
    AgentActionContextInjectionMode? injectionMode,
  }) {
    return AgentActionContextPolicy(
      allowedContextExtensions: allowedContextExtensions ?? this.allowedContextExtensions,
      maxContextBytes: maxContextBytes ?? this.maxContextBytes,
      contextJsonSchema: clearContextJsonSchema ? null : (contextJsonSchema ?? this.contextJsonSchema),
      runtimeParameterSchema: clearRuntimeParameterSchema
          ? null
          : (runtimeParameterSchema ?? this.runtimeParameterSchema),
      injectionMode: injectionMode ?? this.injectionMode,
    );
  }

  bool allowsExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return allowedContextExtensions.contains(
      normalized.startsWith('.') ? normalized : '.$normalized',
    );
  }
}

class AgentActionExitCodePolicy {
  const AgentActionExitCodePolicy({
    this.acceptedExitCodes = const {0},
  });

  final Set<int> acceptedExitCodes;

  bool isAccepted(int exitCode) => acceptedExitCodes.contains(exitCode);

  AgentActionExitCodePolicy copyWith({
    Set<int>? acceptedExitCodes,
  }) {
    return AgentActionExitCodePolicy(
      acceptedExitCodes: acceptedExitCodes ?? this.acceptedExitCodes,
    );
  }
}

class AgentActionProcessPolicy {
  const AgentActionProcessPolicy({
    this.windowMode = AgentActionProcessWindowMode.normal,
  });

  final AgentActionProcessWindowMode windowMode;

  AgentActionProcessPolicy copyWith({
    AgentActionProcessWindowMode? windowMode,
  }) {
    return AgentActionProcessPolicy(
      windowMode: windowMode ?? this.windowMode,
    );
  }
}

class AgentActionLifecyclePolicy {
  const AgentActionLifecyclePolicy({
    this.onAppExit = AgentActionOnAppExitBehavior.killMainProcess,
    this.waitBeforeKillOnAppExit = const Duration(seconds: 5),
  });

  final AgentActionOnAppExitBehavior onAppExit;
  final Duration waitBeforeKillOnAppExit;

  AgentActionLifecyclePolicy copyWith({
    AgentActionOnAppExitBehavior? onAppExit,
    Duration? waitBeforeKillOnAppExit,
  }) {
    return AgentActionLifecyclePolicy(
      onAppExit: onAppExit ?? this.onAppExit,
      waitBeforeKillOnAppExit: waitBeforeKillOnAppExit ?? this.waitBeforeKillOnAppExit,
    );
  }
}

class AgentActionRetryPolicy {
  const AgentActionRetryPolicy({
    this.maxAttempts = 1,
    this.allowRemote = false,
    this.delayBetweenAttempts = Duration.zero,
  });

  final int maxAttempts;
  final bool allowRemote;
  final Duration delayBetweenAttempts;

  int effectiveMaxAttempts(
    AgentActionExecutionRequest request, {
    bool runElevated = false,
  }) {
    final configured = maxAttempts < 1 ? 1 : maxAttempts;
    if (configured <= 1) {
      return 1;
    }
    if (runElevated) {
      return 1;
    }
    if (request.source == AgentActionRequestSource.remoteHub && !allowRemote) {
      return 1;
    }

    return configured;
  }

  bool isRetriableStatus(AgentActionExecutionStatus status) {
    return switch (status) {
      AgentActionExecutionStatus.failed || AgentActionExecutionStatus.timedOut => true,
      _ => false,
    };
  }

  AgentActionRetryPolicy copyWith({
    int? maxAttempts,
    bool? allowRemote,
    Duration? delayBetweenAttempts,
  }) {
    return AgentActionRetryPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      allowRemote: allowRemote ?? this.allowRemote,
      delayBetweenAttempts: delayBetweenAttempts ?? this.delayBetweenAttempts,
    );
  }
}

class AgentActionNotificationPolicy {
  const AgentActionNotificationPolicy({
    this.notifyOnSuccess = false,
    this.notifyOnFailure = false,
    this.notifyOnTimeout = false,
  });

  final bool notifyOnSuccess;
  final bool notifyOnFailure;
  final bool notifyOnTimeout;

  bool shouldNotifyFor(AgentActionExecutionStatus status) {
    return switch (status) {
      AgentActionExecutionStatus.succeeded => notifyOnSuccess,
      AgentActionExecutionStatus.timedOut => notifyOnTimeout,
      AgentActionExecutionStatus.failed ||
      AgentActionExecutionStatus.killed ||
      AgentActionExecutionStatus.cancelled ||
      AgentActionExecutionStatus.interrupted ||
      AgentActionExecutionStatus.unknown => notifyOnFailure,
      AgentActionExecutionStatus.skipped => false,
      _ => false,
    };
  }

  AgentActionNotificationPolicy copyWith({
    bool? notifyOnSuccess,
    bool? notifyOnFailure,
    bool? notifyOnTimeout,
  }) {
    return AgentActionNotificationPolicy(
      notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
      notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
      notifyOnTimeout: notifyOnTimeout ?? this.notifyOnTimeout,
    );
  }
}

class AgentActionEnvironmentPolicy {
  const AgentActionEnvironmentPolicy({
    this.allowedProfiles = const {},
    this.allowedVariableNames = const {},
    this.variables = const {},
  });

  final Set<String> allowedProfiles;

  /// When non-empty, only these names may appear in [variables] or runtime env injection.
  final Set<String> allowedVariableNames;

  /// Literal values or `${secret:name}` placeholders applied to the child process environment.
  final Map<String, String> variables;

  bool allowsProfile(String? profile) {
    if (allowedProfiles.isEmpty) {
      return true;
    }
    if (profile == null || profile.trim().isEmpty) {
      return false;
    }

    return allowedProfiles.contains(profile.trim());
  }

  bool allowsVariableName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (allowedVariableNames.isEmpty) {
      return true;
    }

    return allowedVariableNames.contains(normalized);
  }

  AgentActionEnvironmentPolicy copyWith({
    Set<String>? allowedProfiles,
    Set<String>? allowedVariableNames,
    Map<String, String>? variables,
  }) {
    return AgentActionEnvironmentPolicy(
      allowedProfiles: allowedProfiles ?? this.allowedProfiles,
      allowedVariableNames: allowedVariableNames ?? this.allowedVariableNames,
      variables: variables ?? this.variables,
    );
  }
}

class AgentActionPathPolicy {
  const AgentActionPathPolicy({
    this.allowedWorkingDirectories = const {},
    this.allowedContextDirectories = const {},
  });

  final Set<String> allowedWorkingDirectories;
  final Set<String> allowedContextDirectories;
}

class AgentActionElevatedPolicy {
  const AgentActionElevatedPolicy({
    this.runElevated = false,
  });

  final bool runElevated;

  AgentActionElevatedPolicy copyWith({
    bool? runElevated,
  }) {
    return AgentActionElevatedPolicy(
      runElevated: runElevated ?? this.runElevated,
    );
  }
}

class AgentActionDefinitionPolicies {
  const AgentActionDefinitionPolicies({
    this.remote = const AgentActionRemotePolicy(),
    this.queue = const AgentActionQueuePolicy(),
    this.timeout = const AgentActionTimeoutPolicy(),
    this.capture = const AgentActionCapturePolicy(),
    this.context = const AgentActionContextPolicy(),
    this.exitCode = const AgentActionExitCodePolicy(),
    this.lifecycle = const AgentActionLifecyclePolicy(),
    this.process = const AgentActionProcessPolicy(),
    this.retry = const AgentActionRetryPolicy(),
    this.notification = const AgentActionNotificationPolicy(),
    this.environment = const AgentActionEnvironmentPolicy(),
    this.path = const AgentActionPathPolicy(),
    this.elevated = const AgentActionElevatedPolicy(),
    this.encoding = const AgentActionEncodingPolicy(),
  });

  final AgentActionRemotePolicy remote;
  final AgentActionQueuePolicy queue;
  final AgentActionTimeoutPolicy timeout;
  final AgentActionCapturePolicy capture;
  final AgentActionContextPolicy context;
  final AgentActionExitCodePolicy exitCode;
  final AgentActionLifecyclePolicy lifecycle;
  final AgentActionProcessPolicy process;
  final AgentActionRetryPolicy retry;
  final AgentActionNotificationPolicy notification;
  final AgentActionEnvironmentPolicy environment;
  final AgentActionPathPolicy path;
  final AgentActionElevatedPolicy elevated;
  final AgentActionEncodingPolicy encoding;

  AgentActionDefinitionPolicies copyWith({
    AgentActionRemotePolicy? remote,
    AgentActionQueuePolicy? queue,
    AgentActionTimeoutPolicy? timeout,
    AgentActionCapturePolicy? capture,
    AgentActionContextPolicy? context,
    AgentActionExitCodePolicy? exitCode,
    AgentActionLifecyclePolicy? lifecycle,
    AgentActionProcessPolicy? process,
    AgentActionRetryPolicy? retry,
    AgentActionNotificationPolicy? notification,
    AgentActionEnvironmentPolicy? environment,
    AgentActionPathPolicy? path,
    AgentActionElevatedPolicy? elevated,
    AgentActionEncodingPolicy? encoding,
  }) {
    return AgentActionDefinitionPolicies(
      remote: remote ?? this.remote,
      queue: queue ?? this.queue,
      timeout: timeout ?? this.timeout,
      capture: capture ?? this.capture,
      context: context ?? this.context,
      exitCode: exitCode ?? this.exitCode,
      lifecycle: lifecycle ?? this.lifecycle,
      process: process ?? this.process,
      retry: retry ?? this.retry,
      notification: notification ?? this.notification,
      environment: environment ?? this.environment,
      path: path ?? this.path,
      elevated: elevated ?? this.elevated,
      encoding: encoding ?? this.encoding,
    );
  }
}
