import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/domain/actions/actions.dart';

class AgentActionDefinitionSnapshotter {
  const AgentActionDefinitionSnapshotter();

  String snapshotHash(AgentActionDefinition definition) {
    final canonicalJson = jsonEncode(_canonicalize(_definitionToSnapshot(definition)));
    return 'sha256:${sha256.convert(utf8.encode(canonicalJson))}';
  }

  /// Redacted hash of fields that require local re-approval when changed after remote enablement.
  ///
  /// When [secretReferenceFingerprints] is provided, `${secret:name}` content hashes
  /// are included so secret rotation invalidates prior remote approval.
  String riskFingerprint(
    AgentActionDefinition definition, {
    Map<String, String>? secretReferenceFingerprints,
  }) {
    final canonicalJson = jsonEncode(
      _canonicalize(
        _riskFieldsToSnapshot(
          definition,
          secretReferenceFingerprints: secretReferenceFingerprints,
        ),
      ),
    );
    return 'sha256:${sha256.convert(utf8.encode(canonicalJson))}';
  }

  Map<String, Object?> _riskFieldsToSnapshot(
    AgentActionDefinition definition, {
    Map<String, String>? secretReferenceFingerprints,
  }) {
    final policies = definition.policies;
    final snapshot = <String, Object?>{
      'type': definition.type.name,
      'config': _configToSnapshot(definition.config),
      'remote': <String, Object?>{
        'isEnabled': policies.remote.isEnabled,
        'allowAdHoc': policies.remote.allowAdHoc,
      },
      'capture': <String, Object?>{
        'redactBeforePersisting': policies.capture.redactBeforePersisting,
      },
      'encoding': <String, Object?>{
        'stdout': policies.encoding.stdout.name,
        'stderr': policies.encoding.stderr.name,
      },
      'context': <String, Object?>{
        'allowedContextExtensions': policies.context.allowedContextExtensions.toList(growable: false),
        'maxContextBytes': policies.context.maxContextBytes,
        'contextJsonSchema': policies.context.contextJsonSchema,
        'runtimeParameterSchema': policies.context.runtimeParameterSchema,
        'injectionMode': policies.context.injectionMode.name,
      },
      'exitCode': <String, Object?>{
        'acceptedExitCodes': policies.exitCode.acceptedExitCodes.toList(growable: false),
      },
      'lifecycle': <String, Object?>{
        'onAppExit': policies.lifecycle.onAppExit.name,
        'waitBeforeKillOnAppExitMs': policies.lifecycle.waitBeforeKillOnAppExit.inMilliseconds,
      },
      'process': <String, Object?>{
        'windowMode': policies.process.windowMode.name,
      },
      'retry': <String, Object?>{
        'allowRemote': policies.retry.allowRemote,
      },
      'elevated': <String, Object?>{
        'runElevated': policies.elevated.runElevated,
      },
      'environment': <String, Object?>{
        'allowedProfiles': policies.environment.allowedProfiles.toList(growable: false),
        'allowedVariableNames': policies.environment.allowedVariableNames.toList(growable: false),
        'variables': Map<String, String>.from(policies.environment.variables),
      },
      'timeout': <String, Object?>{
        'maxRuntimeMs': policies.timeout.maxRuntime.inMilliseconds,
        'killMainProcessOnTimeout': policies.timeout.killMainProcessOnTimeout,
      },
    };
    if (secretReferenceFingerprints != null && secretReferenceFingerprints.isNotEmpty) {
      final sortedEntries = secretReferenceFingerprints.entries.toList()
        ..sort((MapEntry<String, String> a, MapEntry<String, String> b) => a.key.compareTo(b.key));
      snapshot['secretReferenceFingerprints'] = Map<String, String>.fromEntries(sortedEntries);
    }
    return snapshot;
  }

  Map<String, Object?> _definitionToSnapshot(AgentActionDefinition definition) {
    return <String, Object?>{
      'id': definition.id,
      'name': definition.name,
      'description': definition.description,
      'type': definition.type.name,
      'state': definition.state.name,
      'definitionVersion': definition.definitionVersion,
      'config': _configToSnapshot(definition.config),
      'policies': _policiesToSnapshot(definition.policies),
    };
  }

  Map<String, Object?> _configToSnapshot(AgentActionConfig config) {
    return switch (config) {
      CommandLineActionConfig() => <String, Object?>{
        'command': config.command,
        'workingDirectory': _pathToSnapshot(config.workingDirectory),
      },
      ExecutableActionConfig() => <String, Object?>{
        'executablePath': _pathToSnapshot(config.executablePath),
        'arguments': config.arguments,
        'workingDirectory': _pathToSnapshot(config.workingDirectory),
      },
      ScriptActionConfig() => <String, Object?>{
        'scriptPath': _pathToSnapshot(config.scriptPath),
        'interpreterPath': _pathToSnapshot(config.interpreterPath),
        'arguments': config.arguments,
        'workingDirectory': _pathToSnapshot(config.workingDirectory),
      },
      JarActionConfig() => <String, Object?>{
        'jarPath': _pathToSnapshot(config.jarPath),
        'javaExecutablePath': _pathToSnapshot(config.javaExecutablePath),
        'arguments': config.arguments,
        'workingDirectory': _pathToSnapshot(config.workingDirectory),
      },
      EmailActionConfig() => <String, Object?>{
        'smtpProfileId': config.smtpProfileId,
        'from': config.from,
        'to': config.to,
        'cc': config.cc,
        'bcc': config.bcc,
        'subjectTemplate': config.subjectTemplate,
        'bodyTemplate': config.bodyTemplate,
        'attachmentPaths': config.attachmentPaths.map(_pathToSnapshot).toList(growable: false),
      },
      ComObjectActionConfig() => <String, Object?>{
        'progId': config.progId,
        'memberName': config.memberName,
        'arguments': config.arguments,
      },
      DeveloperActionConfig() => <String, Object?>{
        'engine': config.engine.name,
        'executorPath': _pathToSnapshot(config.executorPath),
        'projectPath': _pathToSnapshot(config.projectPath),
        'data7ConfigPath': _pathToSnapshot(config.data7ConfigPath),
        'connectionId': config.connectionId,
        'connectionLabel': config.connectionLabel,
        'connectionSnapshotHash': config.connectionSnapshotHash,
      },
    };
  }

  Map<String, Object?> _policiesToSnapshot(AgentActionDefinitionPolicies policies) {
    return <String, Object?>{
      'remote': <String, Object?>{
        'isEnabled': policies.remote.isEnabled,
        'allowAdHoc': policies.remote.allowAdHoc,
        'approvedBy': policies.remote.approvedBy,
        'approvedAt': policies.remote.approvedAt?.toUtc().toIso8601String(),
        'approvalReason': policies.remote.approvalReason,
        'riskFingerprint': policies.remote.riskFingerprint,
        'requiresReapproval': policies.remote.requiresReapproval,
      },
      'queue': <String, Object?>{
        'maxConcurrent': policies.queue.maxConcurrent,
        'maxQueued': policies.queue.maxQueued,
        'queueTimeoutMs': policies.queue.queueTimeout.inMilliseconds,
        'concurrencyBehavior': policies.queue.concurrencyBehavior.name,
      },
      'timeout': <String, Object?>{
        'maxRuntimeMs': policies.timeout.maxRuntime.inMilliseconds,
        'killMainProcessOnTimeout': policies.timeout.killMainProcessOnTimeout,
      },
      'capture': <String, Object?>{
        'captureStdout': policies.capture.captureStdout,
        'captureStderr': policies.capture.captureStderr,
        'maxCapturedOutputBytes': policies.capture.maxCapturedOutputBytes,
        'redactBeforePersisting': policies.capture.redactBeforePersisting,
      },
      'encoding': <String, Object?>{
        'stdout': policies.encoding.stdout.name,
        'stderr': policies.encoding.stderr.name,
      },
      'context': <String, Object?>{
        'allowedContextExtensions': policies.context.allowedContextExtensions.toList(growable: false),
        'maxContextBytes': policies.context.maxContextBytes,
        'contextJsonSchema': policies.context.contextJsonSchema,
        'runtimeParameterSchema': policies.context.runtimeParameterSchema,
        'injectionMode': policies.context.injectionMode.name,
      },
      'exitCode': <String, Object?>{
        'acceptedExitCodes': policies.exitCode.acceptedExitCodes.toList(growable: false),
      },
      'lifecycle': <String, Object?>{
        'onAppExit': policies.lifecycle.onAppExit.name,
        'waitBeforeKillOnAppExitMs': policies.lifecycle.waitBeforeKillOnAppExit.inMilliseconds,
      },
      'process': <String, Object?>{
        'windowMode': policies.process.windowMode.name,
      },
      'retry': <String, Object?>{
        'maxAttempts': policies.retry.maxAttempts,
        'allowRemote': policies.retry.allowRemote,
        'delayBetweenAttemptsMs': policies.retry.delayBetweenAttempts.inMilliseconds,
      },
      'notification': <String, Object?>{
        'notifyOnSuccess': policies.notification.notifyOnSuccess,
        'notifyOnFailure': policies.notification.notifyOnFailure,
        'notifyOnTimeout': policies.notification.notifyOnTimeout,
      },
      'environment': <String, Object?>{
        'allowedProfiles': policies.environment.allowedProfiles.toList(growable: false),
        'allowedVariableNames': policies.environment.allowedVariableNames.toList(growable: false),
        'variables': Map<String, String>.from(policies.environment.variables),
      },
      'path': <String, Object?>{
        'allowedWorkingDirectories': policies.path.allowedWorkingDirectories.toList(growable: false),
        'allowedContextDirectories': policies.path.allowedContextDirectories.toList(growable: false),
      },
    };
  }

  Map<String, Object?>? _pathToSnapshot(AgentActionPathReference? path) {
    if (path == null) {
      return null;
    }
    return <String, Object?>{
      'originalPath': path.originalPath,
      'canonicalPath': path.canonicalPath,
      'existsAtValidation': path.existsAtValidation,
      'validatedAt': path.validatedAt?.toUtc().toIso8601String(),
      'validationHash': path.validationHash,
    };
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in sortedKeys) key: _canonicalize(value[key]),
      };
    }
    if (value is Set) {
      final items = value.map(_canonicalize).toList(growable: false);
      items.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      return items;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }
}
