import 'dart:convert';

import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class AgentActionDriftMapper {
  const AgentActionDriftMapper();

  AgentActionDefinitionData definitionToData(
    AgentActionDefinition definition, {
    required DateTime now,
  }) {
    return AgentActionDefinitionData(
      id: definition.id,
      name: definition.name,
      description: definition.description,
      type: definition.type.name,
      state: definition.state.name,
      configJson: jsonEncode(_configToJson(definition.config)),
      policiesJson: jsonEncode(_policiesToJson(definition.policies)),
      definitionVersion: definition.definitionVersion,
      definitionSnapshotHash: definition.definitionSnapshotHash,
      createdAt: definition.createdAt ?? now,
      updatedAt: definition.updatedAt ?? now,
    );
  }

  AgentActionDefinition definitionFromData(
    AgentActionDefinitionData data,
  ) {
    final type = AgentActionType.values.byName(data.type);
    return AgentActionDefinition(
      id: data.id,
      name: data.name,
      description: data.description,
      config: _configFromJson(
        type: type,
        json: _decodeObject(data.configJson),
      ),
      state: AgentActionState.values.byName(data.state),
      policies: _policiesFromJson(_decodeObject(data.policiesJson)),
      definitionVersion: data.definitionVersion,
      definitionSnapshotHash: data.definitionSnapshotHash,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  AgentActionTriggerData triggerToData(
    AgentActionTrigger trigger, {
    required DateTime now,
  }) {
    return AgentActionTriggerData(
      id: trigger.id,
      actionId: trigger.actionId,
      type: trigger.type.name,
      name: trigger.name,
      isEnabled: trigger.isEnabled,
      scheduleJson: jsonEncode(_triggerScheduleToJson(trigger.schedule)),
      lastScheduledAt: trigger.lastScheduledAt,
      lastRunAt: trigger.lastRunAt,
      nextRunAt: trigger.nextRunAt,
      createdAt: trigger.createdAt ?? now,
      updatedAt: trigger.updatedAt ?? now,
    );
  }

  AgentActionTrigger triggerFromData(
    AgentActionTriggerData data,
  ) {
    return AgentActionTrigger(
      id: data.id,
      actionId: data.actionId,
      type: AgentActionTriggerType.values.byName(data.type),
      name: data.name,
      isEnabled: data.isEnabled,
      schedule: _triggerScheduleFromJson(_decodeObject(data.scheduleJson)),
      lastScheduledAt: data.lastScheduledAt,
      lastRunAt: data.lastRunAt,
      nextRunAt: data.nextRunAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  AgentActionExecutionData executionToData(
    AgentActionExecution execution,
  ) {
    return AgentActionExecutionData(
      id: execution.id,
      actionId: execution.actionId,
      actionType: execution.actionType.name,
      status: execution.status.name,
      requestedAt: execution.requestedAt,
      source: execution.source.name,
      idempotencyKey: execution.idempotencyKey,
      requestedBy: execution.requestedBy,
      traceId: execution.traceId,
      runtimeInstanceId: execution.runtimeInstanceId,
      runtimeSessionId: execution.runtimeSessionId,
      triggerId: execution.triggerId,
      triggerType: execution.triggerType?.name,
      scheduledAt: execution.scheduledAt,
      triggeredAt: execution.triggeredAt,
      queueStartedAt: execution.queueStartedAt,
      processStartedAt: execution.processStartedAt,
      finishedAt: execution.finishedAt,
      timeoutAt: execution.timeoutAt,
      pid: execution.pid,
      exitCode: execution.exitCode,
      processExecutable: execution.processExecutable,
      processArgumentCount: execution.processArgumentCount,
      processCommandPreview: execution.processCommandPreview,
      stdoutText: execution.stdoutText,
      stderrText: execution.stderrText,
      stdoutTruncated: execution.stdoutTruncated,
      stderrTruncated: execution.stderrTruncated,
      stdoutStoredInChunks: execution.stdoutStoredInChunks,
      stderrStoredInChunks: execution.stderrStoredInChunks,
      definitionSnapshotHash: execution.definitionSnapshotHash,
      contextHash: execution.contextHash,
      redactionApplied: execution.redactionApplied,
      failureCode: execution.failureCode,
      failurePhase: execution.failurePhase,
      failureMessage: execution.failureMessage,
    );
  }

  AgentActionExecution executionFromData(
    AgentActionExecutionData data,
  ) {
    return AgentActionExecution(
      id: data.id,
      actionId: data.actionId,
      actionType: AgentActionType.values.byName(data.actionType),
      status: AgentActionExecutionStatus.values.byName(data.status),
      requestedAt: data.requestedAt,
      source: AgentActionRequestSource.values.byName(data.source),
      idempotencyKey: data.idempotencyKey,
      requestedBy: data.requestedBy,
      traceId: data.traceId,
      runtimeInstanceId: data.runtimeInstanceId,
      runtimeSessionId: data.runtimeSessionId,
      triggerId: data.triggerId,
      triggerType: _parseOptionalTriggerType(data.triggerType),
      scheduledAt: data.scheduledAt,
      triggeredAt: data.triggeredAt,
      queueStartedAt: data.queueStartedAt,
      processStartedAt: data.processStartedAt,
      finishedAt: data.finishedAt,
      timeoutAt: data.timeoutAt,
      pid: data.pid,
      exitCode: data.exitCode,
      processExecutable: data.processExecutable,
      processArgumentCount: data.processArgumentCount,
      processCommandPreview: data.processCommandPreview,
      stdoutText: data.stdoutText,
      stderrText: data.stderrText,
      stdoutTruncated: data.stdoutTruncated,
      stderrTruncated: data.stderrTruncated,
      stdoutStoredInChunks: data.stdoutStoredInChunks,
      stderrStoredInChunks: data.stderrStoredInChunks,
      definitionSnapshotHash: data.definitionSnapshotHash,
      contextHash: data.contextHash,
      redactionApplied: data.redactionApplied,
      failureCode: data.failureCode,
      failurePhase: data.failurePhase,
      failureMessage: data.failureMessage,
    );
  }

  Map<String, Object?> _configToJson(AgentActionConfig config) {
    return switch (config) {
      CommandLineActionConfig() => {
        'command': config.command,
        if (config.workingDirectory != null) 'workingDirectory': _pathToJson(config.workingDirectory),
      },
      ExecutableActionConfig() => {
        'executablePath': _pathToJson(config.executablePath),
        'arguments': config.arguments,
        if (config.workingDirectory != null) 'workingDirectory': _pathToJson(config.workingDirectory),
      },
      ScriptActionConfig() => {
        'scriptPath': _pathToJson(config.scriptPath),
        if (config.interpreterPath != null) 'interpreterPath': _pathToJson(config.interpreterPath),
        'arguments': config.arguments,
        if (config.workingDirectory != null) 'workingDirectory': _pathToJson(config.workingDirectory),
      },
      JarActionConfig() => {
        'jarPath': _pathToJson(config.jarPath),
        if (config.javaExecutablePath != null) 'javaExecutablePath': _pathToJson(config.javaExecutablePath),
        'arguments': config.arguments,
        if (config.workingDirectory != null) 'workingDirectory': _pathToJson(config.workingDirectory),
      },
      EmailActionConfig() => {
        'smtpProfileId': config.smtpProfileId,
        'from': config.from,
        'to': config.to,
        'cc': config.cc,
        'bcc': config.bcc,
        'subjectTemplate': config.subjectTemplate,
        'bodyTemplate': config.bodyTemplate,
        'attachmentPaths': config.attachmentPaths.map(_pathToJson).toList(growable: false),
      },
      ComObjectActionConfig() => {
        'progId': config.progId,
        'memberName': config.memberName,
        'arguments': config.arguments,
      },
      DeveloperActionConfig() => {
        'engine': config.engine.name,
        'executorPath': _pathToJson(config.executorPath),
        'projectPath': _pathToJson(config.projectPath),
        'data7ConfigPath': _pathToJson(config.data7ConfigPath),
        'connectionId': config.connectionId,
        'connectionLabel': config.connectionLabel,
        'connectionSnapshotHash': config.connectionSnapshotHash,
      },
    };
  }

  AgentActionConfig _configFromJson({
    required AgentActionType type,
    required Map<String, Object?> json,
  }) {
    return switch (type) {
      AgentActionType.commandLine => CommandLineActionConfig(
        command: _readString(json, 'command'),
        workingDirectory: _readOptionalPath(json, 'workingDirectory'),
      ),
      AgentActionType.executable => ExecutableActionConfig(
        executablePath: _readPath(json, 'executablePath'),
        arguments: _readStringList(json, 'arguments'),
        workingDirectory: _readOptionalPath(json, 'workingDirectory'),
      ),
      AgentActionType.script => ScriptActionConfig(
        scriptPath: _readPath(json, 'scriptPath'),
        interpreterPath: _readOptionalPath(json, 'interpreterPath'),
        arguments: _readStringList(json, 'arguments'),
        workingDirectory: _readOptionalPath(json, 'workingDirectory'),
      ),
      AgentActionType.jar => JarActionConfig(
        jarPath: _readPath(json, 'jarPath'),
        javaExecutablePath: _readOptionalPath(json, 'javaExecutablePath'),
        arguments: _readStringList(json, 'arguments'),
        workingDirectory: _readOptionalPath(json, 'workingDirectory'),
      ),
      AgentActionType.email => EmailActionConfig(
        smtpProfileId: _readString(json, 'smtpProfileId'),
        from: _readString(json, 'from'),
        to: _readStringList(json, 'to'),
        cc: _readStringList(json, 'cc'),
        bcc: _readStringList(json, 'bcc'),
        subjectTemplate: _readString(json, 'subjectTemplate'),
        bodyTemplate: _readString(json, 'bodyTemplate'),
        attachmentPaths: _readObjectList(json, 'attachmentPaths').map(_pathFromJson).toList(growable: false),
      ),
      AgentActionType.comObject => ComObjectActionConfig(
        progId: _readString(json, 'progId'),
        memberName: _readString(json, 'memberName'),
        arguments: _readObject(json, 'arguments'),
      ),
      AgentActionType.developer => DeveloperActionConfig.data7Executor(
        executorPath: _readPath(json, 'executorPath'),
        projectPath: _readPath(json, 'projectPath'),
        data7ConfigPath: _readPath(json, 'data7ConfigPath'),
        connectionId: _readString(json, 'connectionId'),
        connectionLabel: _readString(json, 'connectionLabel'),
        connectionSnapshotHash: json['connectionSnapshotHash'] as String?,
      ),
    };
  }

  Map<String, Object?> _policiesToJson(
    AgentActionDefinitionPolicies policies,
  ) {
    return {
      'remote': {
        'isEnabled': policies.remote.isEnabled,
        'allowAdHoc': policies.remote.allowAdHoc,
        'approvedBy': policies.remote.approvedBy,
        'approvedAt': policies.remote.approvedAt?.toIso8601String(),
        'approvalReason': policies.remote.approvalReason,
        'riskFingerprint': policies.remote.riskFingerprint,
        'requiresReapproval': policies.remote.requiresReapproval,
      },
      'queue': {
        'maxConcurrent': policies.queue.maxConcurrent,
        'maxQueued': policies.queue.maxQueued,
        'queueTimeoutMs': policies.queue.queueTimeout.inMilliseconds,
        'concurrencyBehavior': policies.queue.concurrencyBehavior.name,
      },
      'timeout': {
        'maxRuntimeMs': policies.timeout.maxRuntime.inMilliseconds,
        'killMainProcessOnTimeout': policies.timeout.killMainProcessOnTimeout,
      },
      'capture': {
        'captureStdout': policies.capture.captureStdout,
        'captureStderr': policies.capture.captureStderr,
        'maxCapturedOutputBytes': policies.capture.maxCapturedOutputBytes,
        'redactBeforePersisting': policies.capture.redactBeforePersisting,
      },
      'encoding': {
        'stdout': policies.encoding.stdout.name,
        'stderr': policies.encoding.stderr.name,
      },
      'context': {
        'allowedContextExtensions': policies.context.allowedContextExtensions.toList(growable: false),
        'maxContextBytes': policies.context.maxContextBytes,
        'contextJsonSchema': policies.context.contextJsonSchema,
        'runtimeParameterSchema': policies.context.runtimeParameterSchema,
        'injectionMode': policies.context.injectionMode.name,
      },
      'exitCode': {
        'acceptedExitCodes': policies.exitCode.acceptedExitCodes.toList(growable: false),
        'successExitCodes': policies.exitCode.acceptedExitCodes.toList(growable: false),
      },
      'lifecycle': {
        'onAppExit': policies.lifecycle.onAppExit.name,
        'waitBeforeKillOnAppExitMs': policies.lifecycle.waitBeforeKillOnAppExit.inMilliseconds,
      },
      'process': {
        'windowMode': policies.process.windowMode.name,
      },
      'retry': {
        'maxAttempts': policies.retry.maxAttempts,
        'allowRemote': policies.retry.allowRemote,
        'delayBetweenAttemptsMs': policies.retry.delayBetweenAttempts.inMilliseconds,
      },
      'notification': {
        'notifyOnSuccess': policies.notification.notifyOnSuccess,
        'notifyOnFailure': policies.notification.notifyOnFailure,
        'notifyOnTimeout': policies.notification.notifyOnTimeout,
      },
      'environment': {
        'allowedProfiles': policies.environment.allowedProfiles.toList(growable: false),
        'allowedVariableNames': policies.environment.allowedVariableNames.toList(growable: false),
        'variables': Map<String, String>.from(policies.environment.variables),
      },
      'path': {
        'allowedWorkingDirectories': policies.path.allowedWorkingDirectories.toList(growable: false),
        'allowedContextDirectories': policies.path.allowedContextDirectories.toList(growable: false),
      },
      'elevated': {
        'runElevated': policies.elevated.runElevated,
      },
    };
  }

  Map<String, Object?> _triggerScheduleToJson(
    AgentActionTriggerSchedule schedule,
  ) {
    return {
      'startAt': schedule.startAt?.toIso8601String(),
      'endAt': schedule.endAt?.toIso8601String(),
      'intervalMs': schedule.interval?.inMilliseconds,
      'timeOfDayMinutes': schedule.timeOfDayMinutes,
      'weekdays': schedule.weekdays.toList(growable: false),
      'dayOfMonth': schedule.dayOfMonth,
      'timezoneId': schedule.timezoneId,
      'ignoreMissedRuns': schedule.ignoreMissedRuns,
    };
  }

  AgentActionTriggerSchedule _triggerScheduleFromJson(
    Map<String, Object?> json,
  ) {
    final intervalMs = json['intervalMs'] as int?;
    return AgentActionTriggerSchedule(
      startAt: _parseOptionalDate(json['startAt'] as String?),
      endAt: _parseOptionalDate(json['endAt'] as String?),
      interval: intervalMs == null ? null : Duration(milliseconds: intervalMs),
      timeOfDayMinutes: json['timeOfDayMinutes'] as int?,
      weekdays: _readIntList(json, 'weekdays').toSet(),
      dayOfMonth: json['dayOfMonth'] as int?,
      timezoneId: json['timezoneId'] as String?,
      ignoreMissedRuns: json['ignoreMissedRuns'] as bool? ?? true,
    );
  }

  AgentActionDefinitionPolicies _policiesFromJson(
    Map<String, Object?> json,
  ) {
    final remote = _readObject(json, 'remote');
    final queue = _readObject(json, 'queue');
    final timeout = _readObject(json, 'timeout');
    final capture = _readObject(json, 'capture');
    final encoding = _readObject(json, 'encoding');
    final context = _readObject(json, 'context');
    final exitCode = _readObject(json, 'exitCode');
    final lifecycle = _readObject(json, 'lifecycle');
    final process = _readObject(json, 'process');
    final retry = _readObject(json, 'retry');
    final notification = _readObject(json, 'notification');
    final environment = _readObject(json, 'environment');
    final path = _readObject(json, 'path');
    final elevated = _readObject(json, 'elevated');

    return AgentActionDefinitionPolicies(
      remote: AgentActionRemotePolicy(
        isEnabled: remote['isEnabled'] as bool? ?? false,
        allowAdHoc: remote['allowAdHoc'] as bool? ?? false,
        approvedBy: remote['approvedBy'] as String?,
        approvedAt: _parseOptionalDate(remote['approvedAt'] as String?),
        approvalReason: remote['approvalReason'] as String?,
        riskFingerprint: remote['riskFingerprint'] as String?,
        requiresReapproval: remote['requiresReapproval'] as bool? ?? false,
      ),
      queue: AgentActionQueuePolicy(
        maxConcurrent: queue['maxConcurrent'] as int? ?? 1,
        maxQueued: queue['maxQueued'] as int? ?? 100,
        queueTimeout: Duration(
          milliseconds: queue['queueTimeoutMs'] as int? ?? const Duration(minutes: 5).inMilliseconds,
        ),
        concurrencyBehavior: AgentActionConcurrencyBehavior.values.byName(
          queue['concurrencyBehavior'] as String? ?? AgentActionConcurrencyBehavior.enqueue.name,
        ),
      ),
      timeout: AgentActionTimeoutPolicy(
        maxRuntime: Duration(
          milliseconds: timeout['maxRuntimeMs'] as int? ?? const Duration(minutes: 30).inMilliseconds,
        ),
        killMainProcessOnTimeout: timeout['killMainProcessOnTimeout'] as bool? ?? true,
      ),
      capture: AgentActionCapturePolicy(
        captureStdout: capture['captureStdout'] as bool? ?? true,
        captureStderr: capture['captureStderr'] as bool? ?? true,
        maxCapturedOutputBytes: capture['maxCapturedOutputBytes'] as int? ?? 64 * 1024,
        redactBeforePersisting: capture['redactBeforePersisting'] as bool? ?? true,
      ),
      encoding: AgentActionEncodingPolicy(
        stdout: AgentActionOutputEncodingMode.values.byName(
          encoding['stdout'] as String? ?? AgentActionOutputEncodingMode.systemConsole.name,
        ),
        stderr: AgentActionOutputEncodingMode.values.byName(
          encoding['stderr'] as String? ?? AgentActionOutputEncodingMode.systemConsole.name,
        ),
      ),
      context: AgentActionContextPolicy(
        allowedContextExtensions: _readStringList(
          context,
          'allowedContextExtensions',
          fallback: const ['.txt', '.json'],
        ).toSet(),
        maxContextBytes: context['maxContextBytes'] as int? ?? 256 * 1024,
        contextJsonSchema: context['contextJsonSchema'] as Map<String, Object?>?,
        runtimeParameterSchema: context['runtimeParameterSchema'] as Map<String, Object?>?,
        injectionMode: AgentActionContextInjectionMode.values.byName(
          context['injectionMode'] as String? ?? AgentActionContextInjectionMode.argument.name,
        ),
      ),
      exitCode: AgentActionExitCodePolicy(
        acceptedExitCodes: _readAcceptedExitCodes(exitCode),
      ),
      lifecycle: AgentActionLifecyclePolicy(
        onAppExit: AgentActionOnAppExitBehavior.values.byName(
          lifecycle['onAppExit'] as String? ?? AgentActionOnAppExitBehavior.killMainProcess.name,
        ),
        waitBeforeKillOnAppExit: Duration(
          milliseconds: lifecycle['waitBeforeKillOnAppExitMs'] as int? ?? const Duration(seconds: 5).inMilliseconds,
        ),
      ),
      process: AgentActionProcessPolicy(
        windowMode: AgentActionProcessWindowMode.values.byName(
          process['windowMode'] as String? ?? AgentActionProcessWindowMode.normal.name,
        ),
      ),
      retry: AgentActionRetryPolicy(
        maxAttempts: retry['maxAttempts'] as int? ?? 1,
        allowRemote: retry['allowRemote'] as bool? ?? false,
        delayBetweenAttempts: Duration(
          milliseconds: retry['delayBetweenAttemptsMs'] as int? ?? 0,
        ),
      ),
      notification: AgentActionNotificationPolicy(
        notifyOnSuccess: notification['notifyOnSuccess'] as bool? ?? false,
        notifyOnFailure: notification['notifyOnFailure'] as bool? ?? false,
        notifyOnTimeout: notification['notifyOnTimeout'] as bool? ?? false,
      ),
      environment: AgentActionEnvironmentPolicy(
        allowedProfiles: _readStringList(environment, 'allowedProfiles').toSet(),
        allowedVariableNames: _readStringList(environment, 'allowedVariableNames').toSet(),
        variables: _readStringMap(environment, 'variables'),
      ),
      path: AgentActionPathPolicy(
        allowedWorkingDirectories: _readStringList(path, 'allowedWorkingDirectories').toSet(),
        allowedContextDirectories: _readStringList(path, 'allowedContextDirectories').toSet(),
      ),
      elevated: AgentActionElevatedPolicy(
        runElevated: elevated['runElevated'] as bool? ?? false,
      ),
    );
  }

  Map<String, Object?> _pathToJson(AgentActionPathReference? path) {
    if (path == null) {
      return const {};
    }
    return {
      'originalPath': path.originalPath,
      'canonicalPath': path.canonicalPath,
      'existsAtValidation': path.existsAtValidation,
      'validatedAt': path.validatedAt?.toIso8601String(),
      'validationHash': path.validationHash,
      if (path.pathChangePolicy != null) 'pathChangePolicy': path.pathChangePolicy!.name,
    };
  }

  AgentActionPathReference _readPath(
    Map<String, Object?> json,
    String key,
  ) {
    return _pathFromJson(_readObject(json, key));
  }

  AgentActionPathReference? _readOptionalPath(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is Map<String, Object?> && value.isEmpty) {
      return null;
    }
    if (value is Map) {
      return _pathFromJson(value.cast<String, Object?>());
    }
    throw FormatException('Expected "$key" to be an object.');
  }

  AgentActionPathReference _pathFromJson(Map<String, Object?> json) {
    return AgentActionPathReference(
      originalPath: _readString(json, 'originalPath'),
      canonicalPath: json['canonicalPath'] as String?,
      existsAtValidation: json['existsAtValidation'] as bool?,
      validatedAt: _parseOptionalDate(json['validatedAt'] as String?),
      validationHash: json['validationHash'] as String?,
      pathChangePolicy: _readPathChangePolicy(json['pathChangePolicy'] as String?),
    );
  }

  AgentActionPathChangePolicy? _readPathChangePolicy(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return AgentActionPathChangePolicy.values.byName(raw.trim());
  }

  Map<String, Object?> _decodeObject(String value) {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    throw const FormatException('Expected JSON object.');
  }

  Map<String, Object?> _readObject(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return {};
    }
    if (value is Map) {
      return value.cast<String, Object?>();
    }
    throw FormatException('Expected "$key" to be an object.');
  }

  List<Map<String, Object?>> _readObjectList(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw FormatException('Expected "$key" to be a list.');
    }
    return value
        .map((item) {
          if (item is Map) {
            return item.cast<String, Object?>();
          }
          throw FormatException('Expected "$key" to contain objects.');
        })
        .toList(growable: false);
  }

  String _readString(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw FormatException('Expected "$key" to be a string.');
  }

  List<String> _readStringList(
    Map<String, Object?> json,
    String key, {
    List<String> fallback = const [],
  }) {
    final value = json[key];
    if (value == null) {
      return fallback;
    }
    if (value is! List) {
      throw FormatException('Expected "$key" to be a list.');
    }
    return value.map((item) => item as String).toList(growable: false);
  }

  Map<String, String> _readStringMap(
    Map<String, Object?> json,
    String key, {
    Map<String, String> fallback = const {},
  }) {
    final value = json[key];
    if (value == null) {
      return fallback;
    }
    if (value is! Map) {
      throw FormatException('Expected "$key" to be an object.');
    }

    return Map<String, String>.unmodifiable(
      value.map(
        (Object? entryKey, Object? entryValue) {
          if (entryKey is! String) {
            throw FormatException('Expected "$key" keys to be strings.');
          }
          if (entryValue is! String) {
            throw FormatException('Expected "$key" values to be strings.');
          }
          return MapEntry(entryKey, entryValue);
        },
      ),
    );
  }

  Set<int> _readAcceptedExitCodes(Map<String, Object?> exitCode) {
    if (exitCode.containsKey('acceptedExitCodes')) {
      return _readIntList(exitCode, 'acceptedExitCodes', fallback: const [0]).toSet();
    }
    if (exitCode.containsKey('successExitCodes')) {
      return _readIntList(exitCode, 'successExitCodes', fallback: const [0]).toSet();
    }

    return const {0};
  }

  List<int> _readIntList(
    Map<String, Object?> json,
    String key, {
    List<int> fallback = const [],
  }) {
    final value = json[key];
    if (value == null) {
      return fallback;
    }
    if (value is! List) {
      throw FormatException('Expected "$key" to be a list.');
    }
    return value.map((item) => item as int).toList(growable: false);
  }

  DateTime? _parseOptionalDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }

  AgentActionTriggerType? _parseOptionalTriggerType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return AgentActionTriggerType.values.byName(value);
  }

  Map<String, Object?> definitionToPortableJson(AgentActionDefinition definition) {
    return <String, Object?>{
      'id': definition.id,
      'name': definition.name,
      'description': definition.description,
      'type': definition.type.name,
      'state': definition.state.name,
      'definitionVersion': definition.definitionVersion,
      'config': _configToJson(definition.config),
      'policies': _policiesToJson(definition.policies),
    };
  }

  Map<String, Object?> triggerToPortableJson(AgentActionTrigger trigger) {
    return <String, Object?>{
      'id': trigger.id,
      'actionId': trigger.actionId,
      'type': trigger.type.name,
      'name': trigger.name,
      'isEnabled': trigger.isEnabled,
      'schedule': _triggerScheduleToJson(trigger.schedule),
    };
  }

  AgentActionDefinition definitionFromPortableJson(Map<String, Object?> json) {
    final type = AgentActionType.values.byName(_readString(json, 'type'));
    final stateRaw = json['state'] as String?;
    return AgentActionDefinition(
      id: _readString(json, 'id'),
      name: _readString(json, 'name'),
      description: json['description'] as String?,
      config: _configFromJson(type: type, json: _readObject(json, 'config')),
      state: stateRaw == null
          ? AgentActionState.needsValidation
          : AgentActionState.values.byName(stateRaw),
      policies: _policiesFromJson(_readObject(json, 'policies')),
      definitionVersion: json['definitionVersion'] as int? ?? 1,
    );
  }

  AgentActionTrigger triggerFromPortableJson(Map<String, Object?> json) {
    return AgentActionTrigger(
      id: _readString(json, 'id'),
      actionId: _readString(json, 'actionId'),
      type: AgentActionTriggerType.values.byName(_readString(json, 'type')),
      name: json['name'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? false,
      schedule: _triggerScheduleFromJson(_readObject(json, 'schedule')),
    );
  }
}
