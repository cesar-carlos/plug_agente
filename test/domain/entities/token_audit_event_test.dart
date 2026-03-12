import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';

void main() {
  group('TokenAuditEventType', () {
    test('should have create, revoke and revokedInSession', () {
      expect(TokenAuditEventType.values.length, 3);
      expect(TokenAuditEventType.values, contains(TokenAuditEventType.create));
      expect(TokenAuditEventType.values, contains(TokenAuditEventType.revoke));
      expect(
        TokenAuditEventType.values,
        contains(TokenAuditEventType.revokedInSession),
      );
    });
  });

  group('TokenAuditEvent', () {
    test('toJson should include event_type and timestamp', () {
      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2025, 3, 12, 10),
      );
      final json = event.toJson();

      expect(json['event_type'], 'create');
      expect(json['timestamp'], '2025-03-12T10:00:00.000Z');
    });

    test('toJson should include client_id when present', () {
      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.revoke,
        timestamp: DateTime.utc(2025, 3, 12),
        clientId: 'client-1',
      );
      final json = event.toJson();

      expect(json['client_id'], 'client-1');
    });

    test('toJson should include token_id when present', () {
      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.revoke,
        timestamp: DateTime.utc(2025, 3, 12),
        tokenId: 'tok-123',
      );
      final json = event.toJson();

      expect(json['token_id'], 'tok-123');
    });

    test('toJson should include metadata when non-empty', () {
      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2025, 3, 12),
        metadata: {'agent_id': 'agent-1'},
      );
      final json = event.toJson();

      expect(json['metadata'], {'agent_id': 'agent-1'});
    });

    test('toJson should omit metadata when empty', () {
      final event = TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2025, 3, 12),
      );
      final json = event.toJson();

      expect(json.containsKey('metadata'), isFalse);
    });
  });
}
