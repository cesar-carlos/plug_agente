import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:uuid/uuid.dart';

/// Per-installation and per-boot identifiers for correlating executions and diagnostics.
final class AgentRuntimeIdentity {
  const AgentRuntimeIdentity({
    required this.runtimeInstanceId,
    required this.runtimeSessionId,
  });

  static const String _settingsKeyInstanceId = 'agent_runtime_instance_id_v1';

  final String runtimeInstanceId;
  final String runtimeSessionId;

  static Future<AgentRuntimeIdentity> load({
    required IAppSettingsStore settings,
    Uuid uuid = const Uuid(),
  }) async {
    var instanceId = settings.getString(_settingsKeyInstanceId)?.trim();
    if (instanceId == null || instanceId.isEmpty) {
      instanceId = 'inst-${uuid.v4()}';
      await settings.setString(_settingsKeyInstanceId, instanceId);
    }
    final sessionId = 'sess-${uuid.v4()}';
    return AgentRuntimeIdentity(
      runtimeInstanceId: instanceId,
      runtimeSessionId: sessionId,
    );
  }
}
