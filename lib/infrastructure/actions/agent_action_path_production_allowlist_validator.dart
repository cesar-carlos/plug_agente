import 'dart:io';

import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_prod_defaults_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_helpers.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_types.dart';

class AgentActionPathProductionAllowlistValidator {
  AgentActionPathProductionAllowlistValidator({
    required AgentActionPathCanonicalizer canonicalizeDirectory,
    AgentActionProductionProfileResolver? isProductionProfile,
  }) : _canonicalizeDirectory = canonicalizeDirectory,
       _isProductionProfile = isProductionProfile ?? _defaultIsProductionProfile;

  final AgentActionPathCanonicalizer _canonicalizeDirectory;
  final AgentActionProductionProfileResolver _isProductionProfile;

  static bool _defaultIsProductionProfile() {
    final raw = AppEnvironment.get(AgentActionGateConstants.operationalProfileEnvironmentKey);
    return AgentActionPathProdDefaultsConstants.isProductionProfile(raw);
  }

  String? get currentOperationalProfile {
    return AppEnvironment.get(AgentActionGateConstants.operationalProfileEnvironmentKey);
  }

  bool isProductionProfile() => _isProductionProfile();

  ActionValidationFailure? validateProductionWorkingDirectoryAllowlist({
    required String actionId,
    required AgentActionPathPolicy pathPolicy,
    required String phase,
  }) {
    if (!_isProductionProfile()) {
      return null;
    }
    if (AgentActionPathValidationHelpers.hasNonBlankAllowlist(pathPolicy.allowedWorkingDirectories)) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: 'Production profile requires explicit working directory allowlist.',
      context: {
        'action_id': actionId,
        'field': 'path.allowedWorkingDirectories',
        'phase': phase,
        'reason': AgentActionPathContextConstants.productionPathAllowlistRequiredReason,
        'operational_profile': currentOperationalProfile,
        'user_message': AgentActionPathProdDefaultsConstants.productionAllowlistRequiredUserMessage,
      },
    );
  }

  Future<bool> isWithinAllowedDirectories({
    required String canonicalPath,
    required Set<String> allowedDirectories,
  }) async {
    if (allowedDirectories.isEmpty) {
      if (_isProductionProfile()) {
        return false;
      }
      return true;
    }

    final normalizedPath = AgentActionPathValidationHelpers.normalizePathForComparison(canonicalPath);
    for (final allowedDirectory in allowedDirectories) {
      final trimmed = allowedDirectory.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      try {
        final canonicalAllowedDirectory = await _canonicalizeDirectory(trimmed);
        final normalizedAllowedDirectory = AgentActionPathValidationHelpers.normalizePathForComparison(
          canonicalAllowedDirectory,
        );
        if (normalizedPath == normalizedAllowedDirectory || normalizedPath.startsWith('$normalizedAllowedDirectory/')) {
          return true;
        }
      } on FileSystemException {
        continue;
      } on Exception {
        continue;
      }
    }

    return false;
  }
}
