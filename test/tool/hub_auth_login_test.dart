import 'package:test/test.dart';

import '../../tool/src/hub_auth_login.dart';

void main() {
  group('parseHubLoginResponse', () {
    test('should parse accessToken and refreshToken', () {
      final result = parseHubLoginResponse(<String, dynamic>{
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      });
      expect(result.accessToken, 'access-1');
      expect(result.refreshToken, 'refresh-1');
    });

    test('should accept token alias for accessToken', () {
      final result = parseHubLoginResponse(<String, dynamic>{
        'token': 'access-2',
        'refreshToken': 'refresh-2',
      });
      expect(result.accessToken, 'access-2');
    });

    test('should throw when tokens are missing', () {
      expect(
        () => parseHubLoginResponse(<String, dynamic>{'error': 'bad creds'}),
        throwsA(isA<HubLoginException>()),
      );
    });
  });
}
