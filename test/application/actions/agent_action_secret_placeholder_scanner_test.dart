import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('AgentActionSecretPlaceholderScanner', () {
    test('should collect secret names from command line definition', () {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Mail',
        config: CommandLineActionConfig(
          command: r'curl -H "Authorization: Bearer ${secret:api_token}"',
        ),
      );

      final names = AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);

      expect(names, {'api_token'});
    });

    test('should return empty set when no placeholders are present', () {
      const definition = AgentActionDefinition(
        id: 'action-2',
        name: 'Dir',
        config: CommandLineActionConfig(command: 'dir'),
      );

      expect(
        AgentActionSecretPlaceholderScanner.collectFromDefinition(definition),
        isEmpty,
      );
    });
  });
}
