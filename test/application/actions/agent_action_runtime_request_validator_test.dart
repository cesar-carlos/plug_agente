import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_request_validator.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('AgentActionRuntimeRequestValidator', () {
    const validator = AgentActionRuntimeRequestValidator();

    test('should accept request with json-compatible runtime parameters', () {
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
        requestedBy: 'user-1',
        traceId: 'trace-1',
        runtimeParameters: {
          'dry_run': true,
          'retries': 2,
          'metadata': {
            'origin': 'ui',
          },
          'items': ['a', 1, false],
        },
      );

      final result = validator.validate(request);

      expect(result.isSuccess(), isTrue);
    });

    test('should reject blank optional text fields when provided', () {
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
        requestedBy: '   ',
      );

      final result = validator.validate(request);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidRequestedByReason),
      );
    });

    test('should reject blank context path when provided', () {
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
        contextPath: '   ',
      );

      final result = validator.validate(request);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidContextPathReason),
      );
    });

    test('should reject runtime parameters with unsupported value types', () {
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
        runtimeParameters: {
          'invalid': Duration(seconds: 1),
        },
      );

      final result = validator.validate(request);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidRuntimeParametersReason),
      );
    });
  });
}
