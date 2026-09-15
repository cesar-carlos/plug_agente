import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';

void main() {
  group('parseClientTokenPayloadJson', () {
    test('should return empty map when raw is empty or whitespace', () {
      final a = parseClientTokenPayloadJson('');
      expect(a.error, isNull);
      expect(a.payload, equals(<String, dynamic>{}));

      final b = parseClientTokenPayloadJson('   \n');
      expect(b.error, isNull);
      expect(b.payload, equals(<String, dynamic>{}));
    });

    test('should parse valid JSON object', () {
      final r = parseClientTokenPayloadJson('{"a":1}');
      expect(r.error, isNull);
      expect(r.payload, equals(<String, dynamic>{'a': 1}));
    });

    test('should fail when JSON is not an object', () {
      final r = parseClientTokenPayloadJson('[1,2]');
      expect(r.payload, isNull);
      expect(r.error, ClientTokenPayloadParseError.notAnObject);
    });

    test('should fail on invalid JSON', () {
      final r = parseClientTokenPayloadJson('{');
      expect(r.payload, isNull);
      expect(r.error, ClientTokenPayloadParseError.invalidJson);
    });
  });

  group('validateClientTokenPayload', () {
    test('accepts documented runtime restriction shapes', () {
      expect(
        validateClientTokenPayload({
          'database': 'ERP',
          'token_scope': ['agent.action.run'],
          'agent_actions': {
            'scopes': 'agent.action.cancel',
            'action_ids': ['sync-orders'],
          },
        }),
        isNull,
      );
    });

    test('rejects malformed runtime restriction shapes', () {
      expect(
        validateClientTokenPayload({
          'agent_actions': {'action_ids': 'sync-orders'},
        }),
        ClientTokenPayloadValidationError.runtimeRestrictionsInvalid,
      );
      expect(
        validateClientTokenPayload({'token_scope': 42}),
        ClientTokenPayloadValidationError.runtimeRestrictionsInvalid,
      );
    });
  });
}
