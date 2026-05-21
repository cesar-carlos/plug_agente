import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/infrastructure/external_services/hub_connect_error_auth_heuristics.dart';

void main() {
  group('isHubConnectAuthRelatedMessage', () {
    test('returns false for connection refused', () {
      expect(isHubConnectAuthRelatedMessage('connection refused'), isFalse);
      expect(isHubConnectAuthRelatedMessage('Connection refused on port 443'), isFalse);
    });

    test('returns false for connection reset', () {
      expect(isHubConnectAuthRelatedMessage('connection reset by peer'), isFalse);
    });

    test('returns true for legacy auth substrings', () {
      expect(isHubConnectAuthRelatedMessage('Authentication failed'), isTrue);
      expect(isHubConnectAuthRelatedMessage('Invalid token'), isTrue);
      expect(isHubConnectAuthRelatedMessage('status 401'), isTrue);
    });

    test('returns true for extended hub auth hints', () {
      expect(isHubConnectAuthRelatedMessage('token_expired'), isTrue);
      expect(isHubConnectAuthRelatedMessage('JWT malformed'), isTrue);
      expect(isHubConnectAuthRelatedMessage('forbidden resource'), isTrue);
      expect(isHubConnectAuthRelatedMessage('unauthorized'), isTrue);
    });
  });

  group('isHubConnectAuthRelatedStructured', () {
    test('detects auth via code and reason', () {
      expect(isHubConnectAuthRelatedStructured(code: 'auth_failed'), isTrue);
      expect(isHubConnectAuthRelatedStructured(reason: AuthorizationContextConstants.tokenRevokedReason), isTrue);
      expect(isHubConnectAuthRelatedStructured(code: '401'), isTrue);
      expect(isHubConnectAuthRelatedStructured(code: 'invalid_token'), isTrue);
    });

    test('returns false when code and reason are absent or unrelated', () {
      expect(isHubConnectAuthRelatedStructured(), isFalse);
      expect(isHubConnectAuthRelatedStructured(code: 'rate_limit', reason: 'slow_down'), isFalse);
    });
  });
}
