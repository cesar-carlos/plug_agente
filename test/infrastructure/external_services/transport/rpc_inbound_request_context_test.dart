import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_request_context.dart';

void main() {
  group('extractClientTokenFromRpcParams', () {
    for (final key in const ['client_token', 'clientToken', 'auth']) {
      test('accepts the documented $key alias', () {
        expect(extractClientTokenFromRpcParams({key: '  current-token  '}), 'current-token');
      });
    }

    test('does not coerce nested or non-string credentials', () {
      expect(
        extractClientTokenFromRpcParams({
          'auth': {'token': 'value'},
        }),
        isNull,
      );
      expect(extractClientTokenFromRpcParams({'client_token': 42}), isNull);
    });
  });
}
