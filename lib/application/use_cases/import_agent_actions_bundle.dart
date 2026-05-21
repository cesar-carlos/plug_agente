import 'dart:convert';

import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class ImportAgentActionsBundleSummary {
  const ImportAgentActionsBundleSummary({
    required this.importedDefinitionIds,
    required this.importedTriggerIds,
    required this.secretPlaceholderNames,
  });

  final List<String> importedDefinitionIds;
  final List<String> importedTriggerIds;
  final List<String> secretPlaceholderNames;
}

class ImportAgentActionsBundle {
  ImportAgentActionsBundle(
    this._saveDefinition,
    this._saveTrigger,
    this._sanitizer,
  );

  final SaveAgentActionDefinition _saveDefinition;
  final SaveAgentActionTrigger _saveTrigger;
  final AgentActionBackupSanitizer _sanitizer;

  Future<Result<ImportAgentActionsBundleSummary>> call(String jsonPayload) async {
    final Map<String, Object?> bundle;
    try {
      final decoded = jsonDecode(jsonPayload);
      if (decoded is! Map) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Agent action import bundle must be a JSON object.',
            context: const {'field': 'root'},
          ),
        );
      }
      bundle = Map<String, Object?>.from(decoded.cast<String, Object?>());
    } on Object catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Agent action import bundle is not valid JSON.',
          cause: error,
        ),
      );
    }

    final schema = bundle['export_schema'] as String?;
    if (schema != AgentActionBackupConstants.exportSchemaV1) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported agent action export schema.',
          context: {'export_schema': schema},
        ),
      );
    }

    final definitionMaps = bundle['definitions'];
    if (definitionMaps is! List) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Agent action import bundle is missing definitions array.',
        ),
      );
    }

    final importedDefinitionIds = <String>[];
    final importedTriggerIds = <String>[];

    for (final Object? rawDefinition in definitionMaps) {
      if (rawDefinition is! Map) {
        continue;
      }
      final definition = _sanitizer.prepareDefinitionForImport(
        Map<String, Object?>.from(rawDefinition.cast<String, Object?>()),
      );
      final saveResult = await _saveDefinition(definition);
      if (saveResult.isError()) {
        return Failure(saveResult.exceptionOrNull()!);
      }
      importedDefinitionIds.add(saveResult.getOrThrow().id);
    }

    final triggerMaps = bundle['triggers'];
    if (triggerMaps is List) {
      for (final Object? rawTrigger in triggerMaps) {
        if (rawTrigger is! Map) {
          continue;
        }
        final trigger = _sanitizer.prepareTriggerForImport(
          Map<String, Object?>.from(rawTrigger.cast<String, Object?>()),
        );
        final saveResult = await _saveTrigger(trigger);
        if (saveResult.isError()) {
          return Failure(saveResult.exceptionOrNull()!);
        }
        importedTriggerIds.add(saveResult.getOrThrow().id);
      }
    }

    final secretNames = _sanitizer.secretPlaceholdersInBundle(bundle).toList(growable: false)..sort();

    return Success(
      ImportAgentActionsBundleSummary(
        importedDefinitionIds: importedDefinitionIds,
        importedTriggerIds: importedTriggerIds,
        secretPlaceholderNames: secretNames,
      ),
    );
  }
}
