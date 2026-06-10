import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_authorization_fingerprint.dart';

void main() {
  group('sqlAuthorizationFingerprint', () {
    test('collapses whitespace and lowercases SQL', () {
      expect(
        sqlAuthorizationFingerprint(' SELECT  *  FROM users WHERE id = 1 '),
        sqlAuthorizationFingerprint('select * from users where id = 1'),
      );
    });
  });
}
