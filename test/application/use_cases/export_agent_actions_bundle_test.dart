import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/core/constants/agent_action_backup_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';

import '../../helpers/agent_action_use_case_test_support.dart' show FakeAgentActionRepository;

void main() {
  group('ExportAgentActionsBundle', () {
    test('should export matching triggers in a single listTriggers call', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'One',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions['action-2'] = const AgentActionDefinition(
        id: 'action-2',
        name: 'Two',
        config: CommandLineActionConfig(command: 'whoami'),
      );
      repository.triggers['t-1'] = const AgentActionTrigger(
        id: 't-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      repository.triggers['t-2'] = const AgentActionTrigger(
        id: 't-2',
        actionId: 'action-2',
        type: AgentActionTriggerType.manual,
      );
      repository.triggers['t-other'] = const AgentActionTrigger(
        id: 't-other',
        actionId: 'action-missing',
        type: AgentActionTriggerType.remote,
      );

      final result = await ExportAgentActionsBundle(
        ListAgentActionDefinitions(repository),
        ListAgentActionTriggers(repository),
        AgentActionBackupSanitizer(codec: const AgentActionPortableCodec()),
      ).call(actionIds: const ['action-1']);

      expect(result.isSuccess(), isTrue);
      final bundle = jsonDecode(result.getOrThrow()) as Map<String, dynamic>;
      expect(bundle['export_schema'], AgentActionBackupConstants.exportSchemaV1);
      final definitions = bundle['definitions'] as List<dynamic>;
      expect(definitions, hasLength(1));
      expect((definitions.single as Map)['id'], 'action-1');
      final triggers = bundle['triggers'] as List<dynamic>;
      expect(triggers, hasLength(1));
      expect((triggers.single as Map)['id'], 't-1');
      expect((triggers.single as Map)['isEnabled'], isFalse);
    });
  });
}
