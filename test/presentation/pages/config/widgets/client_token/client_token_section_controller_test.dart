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
      'scopes': ['agent_actions.run', 'agent_actions.validate_run', 'agent_actions.read_execution', 'agent_actions.io'],
    });
  });

  test('rejects a payload that is not a JSON object', () {
    controller.payloadController.text = '[]';

    expect(controller.includeFaithfulActionIoScopes(), isFalse);
    expect(controller.formErrorKey, ClientTokenFormErrorKey.payloadMustBeJsonObject);
    expect(controller.payloadController.text, '[]');
  });

  test('opens a saved payload indented and does not treat that as a change', () {
    final payload = {
      'agent_actions': {
        'scopes': ['agent_actions.run', 'agent_actions.read_execution', 'agent_actions.io'],
      },
    };
    controller.loadTokenIntoForm(
      ClientTokenSummary(
        id: 'token',
        clientId: 'client',
        createdAt: DateTime.utc(2026, 11, 4),
        isRevoked: false,
        allTables: false,
        allViews: false,
        rules: const [],
        payload: payload,
      ),
    );

    expect(
      controller.payloadController.text,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    expect(controller.hasFormChanges(), isFalse);
    expect(controller.payloadIssueKey, isNull);
  });

  test('formats a JSON object and keeps invalid text unchanged', () {
    controller.payloadController.text = '{"database":"erp"}';

    expect(controller.formatPayloadJson(), isTrue);
    expect(
      controller.payloadController.text,
      const JsonEncoder.withIndent('  ').convert({'database': 'erp'}),
    );
    expect(controller.payloadIssueKey, isNull);

    controller.payloadController.text = '{invalid';

    expect(controller.formatPayloadJson(), isFalse);
    expect(controller.payloadController.text, '{invalid');
    expect(controller.formErrorKey, ClientTokenFormErrorKey.payloadInvalidJson);
    expect(controller.payloadIssueKey, ClientTokenFormErrorKey.payloadInvalidJson);
  });

  test('formats a JSON object that fails payload rules and reports that rule', () {
    controller.payloadController.text = '{"database":1}';

    expect(controller.formatPayloadJson(), isFalse);
    expect(jsonDecode(controller.payloadController.text), {'database': 1});
    expect(controller.payloadController.text.contains('\n'), isTrue);
    expect(controller.formErrorKey, ClientTokenFormErrorKey.payloadDatabaseMustBeString);
  });
}
