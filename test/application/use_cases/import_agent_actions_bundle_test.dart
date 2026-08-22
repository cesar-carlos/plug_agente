import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ValidationFailure;
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';
import 'package:result_dart/result_dart.dart';

class MockSaveAgentActionDefinition extends Mock implements SaveAgentActionDefinition {}

class MockSaveAgentActionTrigger extends Mock implements SaveAgentActionTrigger {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AgentActionDefinition(
        id: 'fallback',
        name: 'Fallback',
        config: CommandLineActionConfig(command: 'dir'),
      ),
    );
    registerFallbackValue(
      const AgentActionTrigger(
        id: 'fallback-trigger',
        actionId: 'fallback',
        type: AgentActionTriggerType.remote,
      ),
    );
  });

  Map<String, Object?> definitionJson({required String id}) {
    return <String, Object?>{
      'id': id,
      'name': id,
      'type': AgentActionType.commandLine.name,
      'state': AgentActionState.active.name,
      'config': <String, Object?>{'command': 'dir'},
      'policies': <String, Object?>{},
    };
  }

  group('ImportAgentActionsBundle', () {
    late MockSaveAgentActionDefinition saveDefinition;
    late MockSaveAgentActionTrigger saveTrigger;
    late ImportAgentActionsBundle useCase;

    setUp(() {
      saveDefinition = MockSaveAgentActionDefinition();
      saveTrigger = MockSaveAgentActionTrigger();
      useCase = ImportAgentActionsBundle(
        saveDefinition,
        saveTrigger,
        AgentActionBackupSanitizer(codec: const AgentActionPortableCodec()),
      );
      when(() => saveDefinition(any())).thenAnswer((invocation) async {
        final definition = invocation.positionalArguments.first as AgentActionDefinition;
        return Success(definition);
      });
      when(() => saveTrigger(any())).thenAnswer((invocation) async {
        final trigger = invocation.positionalArguments.first as AgentActionTrigger;
        return Success(trigger);
      });
    });

    test('should reject invalid definition entries before saving anything', () async {
      final payload = jsonEncode(<String, Object?>{
        'export_schema': AgentActionBackupConstants.exportSchemaV1,
        'definitions': <Object?>[
          'not-an-object',
          definitionJson(id: 'action-1'),
        ],
      });

      final result = await useCase(payload);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ValidationFailure;
      expect(failure.context['field'], 'definitions');
      expect(failure.context['index'], 0);
      verifyNever(() => saveDefinition(any()));
    });

    test('should mark a mid-import save failure as a partial import', () async {
      when(() => saveDefinition(any())).thenAnswer((invocation) async {
        final definition = invocation.positionalArguments.first as AgentActionDefinition;
        if (definition.id == 'action-2') {
          return Failure(
            ValidationFailure.withContext(message: 'cannot save action-2'),
          );
        }
        return Success(definition);
      });

      final payload = jsonEncode(<String, Object?>{
        'export_schema': AgentActionBackupConstants.exportSchemaV1,
        'definitions': <Object?>[
          definitionJson(id: 'action-1'),
          definitionJson(id: 'action-2'),
        ],
      });

      final result = await useCase(payload);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ValidationFailure;
      expect(failure.context['partial_import'], isTrue);
      expect(failure.context['imported_definition_ids'], ['action-1']);
      verify(() => saveDefinition(any())).called(2);
      verifyNever(() => saveTrigger(any()));
    });
  });
}
