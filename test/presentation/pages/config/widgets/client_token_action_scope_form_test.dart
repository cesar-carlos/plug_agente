import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ClientTokenSectionController controller;
  setUp(() {
    controller = ClientTokenSectionController(settingsStoreLookup: () => null, onSectionChanged: () {});
    controller.clientIdController.text = 'client';
    controller.agentIdController.text = 'agent';
  });
  tearDown(() => controller.dispose());

  test('submits faithful action permissions without granting SQL access', () {
    final payload = {
      'agent_action_scopes': ['agent_actions.io', 'agent_actions.run', 'agent_actions.read_execution'],
      'agent_actions': {
        'action_ids': ['saved-action'],
      },
    };
    controller.payloadController.text = jsonEncode(payload);
    final request = controller.buildSubmitRequest();
    expect(request, isNotNull);
    expect(request!.payload, payload);
    expect(request.allTables, isFalse);
    expect(request.allViews, isFalse);
    expect(request.globalPermissions.hasAnyPermission, isFalse);
    expect(request.rules, isEmpty);
  });

  test('does not treat unknown or transport-only scopes as an action operation', () {
    for (final scopes in [
      <String>[],
      ['unknown'],
      ['agent_actions.io'],
    ]) {
      controller.payloadController.text = jsonEncode({'agent_action_scopes': scopes});
      expect(controller.buildSubmitRequest(), isNull);
      expect(controller.formErrorKey, ClientTokenFormErrorKey.ruleOrGlobalPermissionsRequired);
    }
  });
}
