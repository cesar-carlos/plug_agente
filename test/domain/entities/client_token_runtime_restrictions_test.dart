import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_runtime_restrictions.dart';

void main() {
  group('ClientTokenRuntimeRestrictions', () {
    test('keeps SQL database and remote-action constraints distinct', () {
      final restrictions = ClientTokenRuntimeRestrictions.fromPayload({
        'database': ' ERP_MAIN ',
        'token_scope': 'agent.action.run, agent.action.cancel',
        'agent_actions': {
          'action_ids': ['sync-orders'],
        },
      });

      expect(restrictions.database, 'ERP_MAIN');
      expect(restrictions.hasRestrictions, isTrue);
      expect(restrictions.agentActionScopes, containsAll(['agent.action.run', 'agent.action.cancel']));
      expect(restrictions.hasActionIdAllowlist, isTrue);
      expect(restrictions.actionIds, {'sync-orders'});
    });

    test('does not infer restrictions from unrelated payload fields', () {
      final restrictions = ClientTokenRuntimeRestrictions.fromPayload({'environment': 'production'});

      expect(restrictions.hasRestrictions, isFalse);
      expect(restrictions.agentActionScopes, isEmpty);
    });

    test('compares equivalent restrictions canonically', () {
      final left = ClientTokenRuntimeRestrictions.fromPayload({
        'database': ' ERP_MAIN ',
        'token_scope': ['AGENT.ACTION.RUN', 'agent.action.cancel'],
        'agent_actions': {
          'action_ids': ['sync-orders', 'refresh-cache'],
        },
      });
      final right = ClientTokenRuntimeRestrictions.fromPayload({
        'database': 'erp_main',
        'token_scope': 'agent.action.cancel, agent.action.run',
        'agent_actions': {
          'action_ids': ['refresh-cache', 'sync-orders'],
        },
      });

      expect(left, right);
      expect(left.hashCode, right.hashCode);
    });
  });
}
