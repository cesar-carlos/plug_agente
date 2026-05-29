import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_definition_assembler.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('AgentActionDefinitionAssembler', () {
    const assembler = AgentActionDefinitionAssembler();

    group('optionalPathReference', () {
      test('should return null for null, empty or whitespace-only input', () {
        expect(assembler.optionalPathReference(null), isNull);
        expect(assembler.optionalPathReference(''), isNull);
        expect(assembler.optionalPathReference('   '), isNull);
      });

      test('should trim and wrap a non-empty path', () {
        final reference = assembler.optionalPathReference('  C:/data/app.exe  ');

        expect(reference, isNotNull);
        expect(reference!.originalPath, 'C:/data/app.exe');
      });
    });

    group('pathReference', () {
      test('should keep the original path and carry the change policy', () {
        const policy = AgentActionPathChangePolicy.warnIfChanged;
        final reference = assembler.pathReference('C:/data/app.exe', pathChangePolicy: policy);

        expect(reference.originalPath, 'C:/data/app.exe');
        expect(reference.pathChangePolicy, policy);
      });
    });

    group('policiesForSave', () {
      AgentActionDefinitionPolicies merge({
        AgentActionDefinition? existing,
        AgentActionEncodingPolicy? encodingPolicy,
      }) {
        return assembler.policiesForSave(
          existing: existing,
          notificationPolicy: const AgentActionNotificationPolicy(),
          retryPolicy: const AgentActionRetryPolicy(),
          timeoutPolicy: const AgentActionTimeoutPolicy(),
          environmentPolicy: const AgentActionEnvironmentPolicy(),
          exitCodePolicy: const AgentActionExitCodePolicy(),
          processPolicy: const AgentActionProcessPolicy(),
          lifecyclePolicy: const AgentActionLifecyclePolicy(),
          remotePolicy: const AgentActionRemotePolicy(),
          elevatedPolicy: const AgentActionElevatedPolicy(),
          encodingPolicy: encodingPolicy,
        );
      }

      const existingWithEncoding = AgentActionDefinition(
        id: 'action-1',
        name: 'Existing',
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          encoding: AgentActionEncodingPolicy(stdout: AgentActionOutputEncodingMode.utf8),
        ),
      );

      test('should preserve the existing encoding policy when not overridden', () {
        final merged = merge(existing: existingWithEncoding);

        expect(merged.encoding.stdout, AgentActionOutputEncodingMode.utf8);
      });

      test('should apply the supplied encoding policy over the existing one', () {
        // Existing uses utf8; override with the default (systemConsole) policy.
        final merged = merge(
          existing: existingWithEncoding,
          encodingPolicy: const AgentActionEncodingPolicy(),
        );

        expect(merged.encoding.stdout, AgentActionOutputEncodingMode.systemConsole);
      });

      test('should apply the supplied policies when there is no existing definition', () {
        final merged = merge(
          encodingPolicy: const AgentActionEncodingPolicy(stdout: AgentActionOutputEncodingMode.utf8),
        );

        expect(merged.encoding.stdout, AgentActionOutputEncodingMode.utf8);
      });
    });
  });
}
