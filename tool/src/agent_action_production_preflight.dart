/// Static production-readiness checks for agent actions (no Flutter runtime).
library;

import 'dart:io';

import 'live_hub_agent_action_env_check.dart';

/// Outcome of [evaluateAgentActionProductionPreflight].
class AgentActionProductionPreflightResult {
  const AgentActionProductionPreflightResult({
    this.ok = const <String>[],
    this.warnings = const <String>[],
    this.failures = const <String>[],
  });

  final List<String> ok;
  final List<String> warnings;
  final List<String> failures;

  bool get isSuccess => failures.isEmpty;
}

String comObjectProductionRegistrationsPath(String projectRoot) =>
    '$projectRoot${Platform.pathSeparator}lib${Platform.pathSeparator}infrastructure${Platform.pathSeparator}actions${Platform.pathSeparator}com_object_production_registrations.dart';

/// Counts non-comment `RegisteredComObjectInvocation(` lines in the production registry file.
int countProductionComObjectRegistrations(String source) {
  var count = 0;
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) {
      continue;
    }
    if (trimmed.contains('RegisteredComObjectInvocation(')) {
      count++;
    }
  }
  return count;
}

bool _comStubEnvComplete(Map<String, String> fileEnv) {
  final enabled = envFlag(fileEnv, 'AGENT_ACTION_COM_STUB_ENABLED');
  if (!enabled) {
    return false;
  }
  final progId = envValue(fileEnv, 'AGENT_ACTION_COM_STUB_PROG_ID');
  final member = envValue(fileEnv, 'AGENT_ACTION_COM_STUB_MEMBER_NAME');
  return progId != null && member != null;
}

AgentActionProductionPreflightResult evaluateAgentActionProductionPreflight({
  required String comRegistrationsSource,
  required Map<String, String> fileEnv,
  required String projectRoot,
  bool strictComHandlers = false,
}) {
  final ok = <String>[];
  final warnings = <String>[];
  final failures = <String>[];

  final productionComHandlers = countProductionComObjectRegistrations(comRegistrationsSource);
  if (productionComHandlers > 0) {
    ok.add('COM production handlers registered: $productionComHandlers');
  } else {
    final stubComplete = _comStubEnvComplete(fileEnv);
    if (stubComplete) {
      warnings.add(
        'No COM handlers in com_object_production_registrations.dart; '
        'AGENT_ACTION_COM_STUB_* enabled for homologation only.',
      );
    } else if (envFlag(fileEnv, 'AGENT_ACTION_COM_STUB_ENABLED')) {
      failures.add(
        'AGENT_ACTION_COM_STUB_ENABLED=true but PROG_ID/MEMBER_NAME are missing in .env.',
      );
    } else {
      const message = 'No COM production handlers and COM stub disabled — comObject actions cannot run.';
      if (strictComHandlers) {
        failures.add(message);
      } else {
        warnings.add('$message Register handlers or enable homologation stub.');
      }
    }
  }

  if (envFlag(fileEnv, 'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS')) {
    final missingLive = missingFromRepoEnv(fileEnv);
    if (missingLive.isNotEmpty) {
      failures.add(
        'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS=true but missing: ${missingLive.join(', ')}.',
      );
    } else {
      ok.add('Live Hub .env variables complete for agent.action.* tests.');
      final readiness = LiveHubEnvReadiness.fromRepoEnv(fileEnv);
      var jwtExpiryWarned = false;
      for (final blocking in readiness.blocking) {
        if (isLiveHubJwtExpiredMessage(blocking)) {
          jwtExpiryWarned = true;
          if (!warnings.contains(blocking)) {
            warnings.add(blocking);
          }
          continue;
        }
        failures.add(blocking);
      }
      for (final w in readiness.warnings) {
        if (jwtExpiryWarned && isLiveHubJwtExpiredMessage(w)) {
          continue;
        }
        if (!warnings.contains(w)) {
          warnings.add(w);
        }
      }
    }
  } else {
    ok.add('Live Hub agent.action RPC tests not enabled in .env (CI/local gate only).');
  }

  final commentedLiveKeys = commentedHubKeysInDotEnv(projectRoot);
  if (commentedLiveKeys.isNotEmpty) {
    warnings.add(
      'Live Hub keys present but commented in .env: ${commentedLiveKeys.join(', ')}.',
    );
  }

  ok.add(
    'Remote rollout defaults (code): enableRemoteAgentActions=false, '
    'enableRemoteAdHocAgentActions=false, enableElevatedAgentActions=false.',
  );

  return AgentActionProductionPreflightResult(
    ok: ok,
    warnings: warnings,
    failures: failures,
  );
}

String readComObjectProductionRegistrationsSource(String projectRoot) {
  return File(comObjectProductionRegistrationsPath(projectRoot)).readAsStringSync();
}
