import 'dart:convert';

import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:result_dart/result_dart.dart';

class ExportAgentActionsBundle {
  ExportAgentActionsBundle(
    this._listDefinitions,
    this._listTriggers,
    this._sanitizer,
  );

  final ListAgentActionDefinitions _listDefinitions;
  final ListAgentActionTriggers _listTriggers;
  final AgentActionBackupSanitizer _sanitizer;

  Future<Result<String>> call({
    List<String>? actionIds,
  }) async {
    final definitionsResult = await _listDefinitions();
    if (definitionsResult.isError()) {
      return Failure(definitionsResult.exceptionOrNull()!);
    }

    var definitions = definitionsResult.getOrThrow();
    if (actionIds != null && actionIds.isNotEmpty) {
      final filter = actionIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
      definitions = definitions.where((definition) => filter.contains(definition.id)).toList(growable: false);
    }

    final triggersResult = await _listTriggers();
    if (triggersResult.isError()) {
      return Failure(triggersResult.exceptionOrNull()!);
    }

    final exportedIds = definitions.map((definition) => definition.id).toSet();
    final triggers = triggersResult
        .getOrThrow()
        .where((trigger) => exportedIds.contains(trigger.actionId))
        .toList(growable: false);

    final bundle = _sanitizer.buildExportBundle(
      definitions: definitions,
      triggers: triggers,
    );

    return Success(const JsonEncoder.withIndent('  ').convert(bundle));
  }
}
