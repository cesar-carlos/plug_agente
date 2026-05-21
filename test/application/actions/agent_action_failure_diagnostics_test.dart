import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:test/test.dart';

void main() {
  group('AgentActionFailureDiagnosticsResolver.userMessage', () {
    test('should prefer user_message when present on ActionFailure', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Technical validation message.',
        context: {
          'user_message': 'Corrija o limite da fila antes de salvar.',
          'phase': AgentActionProcessConstants.definitionValidationPhase,
        },
      );

      expect(
        AgentActionFailureDiagnosticsResolver.userMessage(failure),
        'Corrija o limite da fila antes de salvar.',
      );
    });

    test('should fall back to failure.message when user_message is absent', () {
      final failure = ActionValidationFailure('Validation failed.');

      expect(
        AgentActionFailureDiagnosticsResolver.userMessage(failure),
        'Validation failed.',
      );
    });
  });

  group('AgentActionFailureDiagnosticsResolver.redactedDiagnosticsForTestPreview', () {
    test('should expose phase for test preview when failure context includes phase', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Queue policy is invalid.',
        context: {
          'phase': AgentActionProcessConstants.definitionValidationPhase,
        },
      );

      expect(
        const AgentActionFailureDiagnosticsResolver().redactedDiagnosticsForTestPreview(failure),
        {'phase': AgentActionProcessConstants.definitionValidationPhase},
      );
    });
  });
}
