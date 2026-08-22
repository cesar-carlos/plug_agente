import 'dart:convert';

import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
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

    final preparedDefinitions = <AgentActionDefinition>[];
    for (var index = 0; index < definitionMaps.length; index++) {
      final rawDefinition = definitionMaps[index];
      if (rawDefinition is! Map) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Agent action import bundle contains an invalid definition entry.',
            context: {'field': 'definitions', 'index': index},
          ),
        );
      }
      preparedDefinitions.add(
        _sanitizer.prepareDefinitionForImport(
          Map<String, Object?>.from(rawDefinition.cast<String, Object?>()),
        ),
      );
    }

    final preparedTriggers = <AgentActionTrigger>[];
    final triggerMaps = bundle['triggers'];
    if (triggerMaps != null) {
      if (triggerMaps is! List) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Agent action import bundle triggers must be an array.',
            context: const {'field': 'triggers'},
          ),
        );
      }
      for (var index = 0; index < triggerMaps.length; index++) {
        final rawTrigger = triggerMaps[index];
        if (rawTrigger is! Map) {
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'Agent action import bundle contains an invalid trigger entry.',
              context: {'field': 'triggers', 'index': index},
            ),
          );
        }
        preparedTriggers.add(
          _sanitizer.prepareTriggerForImport(
            Map<String, Object?>.from(rawTrigger.cast<String, Object?>()),
          ),
        );
      }
    }

    final importedDefinitionIds = <String>[];
    final importedTriggerIds = <String>[];

    for (final definition in preparedDefinitions) {
      final saveResult = await _saveDefinition(definition);
      if (saveResult.isError()) {
        return Failure(
          _partialImportFailure(
            saveResult.exceptionOrNull()!,
            importedDefinitionIds: importedDefinitionIds,
            importedTriggerIds: importedTriggerIds,
          ),
        );
      }
      importedDefinitionIds.add(saveResult.getOrThrow().id);
    }

    for (final trigger in preparedTriggers) {
      final saveResult = await _saveTrigger(trigger);
      if (saveResult.isError()) {
        return Failure(
          _partialImportFailure(
            saveResult.exceptionOrNull()!,
            importedDefinitionIds: importedDefinitionIds,
            importedTriggerIds: importedTriggerIds,
          ),
        );
      }
      importedTriggerIds.add(saveResult.getOrThrow().id);
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

  domain.Failure _partialImportFailure(
    Object error, {
    required List<String> importedDefinitionIds,
    required List<String> importedTriggerIds,
  }) {
    if (importedDefinitionIds.isEmpty && importedTriggerIds.isEmpty) {
      return error as domain.Failure;
    }

    final failure = error as domain.Failure;
    return domain.ValidationFailure.withContext(
      message: failure.message,
      cause: failure,
      context: {
        ...failure.context,
        'partial_import': true,
        'imported_definition_ids': List<String>.from(importedDefinitionIds),
        'imported_trigger_ids': List<String>.from(importedTriggerIds),
      },
    );
  }
}
