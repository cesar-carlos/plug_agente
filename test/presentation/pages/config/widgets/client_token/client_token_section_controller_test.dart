import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';

void main() {
  late ClientTokenSectionController controller;

  setUp(() {
    controller = ClientTokenSectionController(
      settingsStoreLookup: () => null,
      onSectionChanged: () {},
    );
  });

  tearDown(() => controller.dispose());

  test('fills an empty Agent ID with this agent and keeps a saved identifier', () {
    controller.loadTokenIntoForm(null, localAgentId: ' b6a1cad3-676f-4f78-90ba-06671f984d9f ');
    expect(controller.agentIdController.text, 'b6a1cad3-676f-4f78-90ba-06671f984d9f');

    controller.loadTokenIntoForm(
      ClientTokenSummary(
        id: 'token',
        clientId: 'client',
        agentId: 'saved-agent',
        createdAt: DateTime.utc(2026, 11, 4),
        isRevoked: false,
        allTables: false,
        allViews: false,
        rules: const [],
      ),
      localAgentId: 'b6a1cad3-676f-4f78-90ba-06671f984d9f',
    );
    expect(controller.agentIdController.text, 'saved-agent');
  });

  test('inserts faithful I/O scopes into an empty payload and preserves other keys', () {
    controller.payloadController.text = jsonEncode({'database': 'erp'});

    expect(controller.includeFaithfulActionIoScopes(), isTrue);

    final payload = jsonDecode(controller.payloadController.text) as Map<String, dynamic>;
    expect(payload['database'], 'erp');
    expect(payload['agent_actions'], {
      'scopes': ['agent_actions.run', 'agent_actions.read_execution', 'agent_actions.io'],
    });
  });

  test('rejects a payload that is not a JSON object', () {
    controller.payloadController.text = '[]';

    expect(controller.includeFaithfulActionIoScopes(), isFalse);
    expect(controller.formErrorKey, ClientTokenFormErrorKey.payloadMustBeJsonObject);
    expect(controller.payloadController.text, '[]');
  });
}
