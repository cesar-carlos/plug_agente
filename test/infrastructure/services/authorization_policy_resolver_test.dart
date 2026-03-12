import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';

void main() {
  group('AuthorizationPolicyResolver', () {
    late AuthorizationPolicyResolver resolver;

    setUp(() {
      resolver = AuthorizationPolicyResolver();
    });

    test('should resolve policy from JWT payload', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'client-acme',
          'all_tables': true,
          'all_views': false,
          'all_permissions': true,
          'rules': const <Map<String, dynamic>>[],
        },
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isSuccess(), isTrue);
      result.fold((policy) {
        expect(policy.clientId, equals('client-acme'));
        expect(policy.allPermissions, isTrue);
      }, (_) => fail('Expected success'));
    });

    test('should return failure for malformed token', () async {
      final result = await resolver.resolvePolicy('invalid-token');

      expect(result.isError(), isTrue);
    });

    test('should return failure for revoked token', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'client-acme',
          'all_tables': false,
          'all_views': false,
          'all_permissions': false,
          'rules': const <Map<String, dynamic>>[],
        },
        'revoked': true,
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isError(), isTrue);
    });
  });
}

String _buildToken(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$encodedPayload.signature';
}
