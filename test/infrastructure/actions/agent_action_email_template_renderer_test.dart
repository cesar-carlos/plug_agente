import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_email_template_renderer.dart';

void main() {
  group('AgentActionEmailTemplateRenderer', () {
    test('should render nested context tokens in templates', () {
      final result = AgentActionEmailTemplateRenderer.render(
        actionId: 'action-1',
        field: 'subjectTemplate',
        template: 'Report {{report.title}}',
        context: <String, Object?>{
          'report': <String, Object?>{
            'title': 'Sales',
          },
        },
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 'Report Sales');
    });

    test('should fail when template tokens remain unresolved', () {
      final result = AgentActionEmailTemplateRenderer.render(
        actionId: 'action-1',
        field: 'bodyTemplate',
        template: 'Hello {{missing}}',
      );

      expect(result.isError(), isTrue);
    });
  });
}
