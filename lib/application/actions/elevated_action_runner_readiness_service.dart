import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

/// Tracks whether the elevated runner helper is installed and operational.
///
/// Until the Windows helper exists, readiness is false unless the installer
/// creates [AgentActionElevatedConstants.readyMarkerFileName].
class ElevatedActionRunnerReadinessService {
  bool _configured = false;
  bool _degraded = false;
  String? _degradedReason;

  bool get isConfigured => _configured;

  bool get isDegraded => _degraded;

  String? get degradedReason => _degradedReason;

  /// Refreshes readiness from the on-disk marker under [context].
  void refresh(GlobalStorageContext context) {
    _configured = File(AgentActionElevatedConstants.readyMarkerPath(context.appDirectoryPath)).existsSync();
  }

  /// Marks the elevated runner as degraded after a helper failure without clearing install state.
  void markDegraded({String? reason}) {
    _degraded = true;
    _degradedReason = reason;
  }

  void clearDegraded() {
    _degraded = false;
    _degradedReason = null;
  }
}
