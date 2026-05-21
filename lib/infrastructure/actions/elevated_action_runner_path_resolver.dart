import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';

/// Resolves the elevated helper executable path for install and validation.
abstract final class ElevatedActionRunnerPathResolver {
  static String? resolveHelperExecutablePath() {
    final fromEnvironment = AppEnvironment.get(AgentActionElevatedConstants.helperExecutableEnvKey);
    if (fromEnvironment != null && File(fromEnvironment).existsSync()) {
      return p.normalize(fromEnvironment);
    }

    final sibling = p.join(
      File(Platform.resolvedExecutable).parent.path,
      AgentActionElevatedConstants.defaultHelperExecutableName,
    );
    if (File(sibling).existsSync()) {
      return p.normalize(sibling);
    }

    return null;
  }
}
