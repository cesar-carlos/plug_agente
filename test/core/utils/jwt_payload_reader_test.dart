import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/jwt_payload_reader.dart';
import 'package:test/test.dart';

String _jwtWithExp(int expSeconds) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode('{"exp":$expSeconds}')).replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  group('JwtPayloadReader.expiryEpochSeconds', () {
    test('should read exp from JWT payload', () {
      check(JwtPayloadReader.expiryEpochSeconds(_jwtWithExp(1_700_000_000))).equals(1_700_000_000);
    });

    test('should return null for invalid token', () {
      check(JwtPayloadReader.expiryEpochSeconds('not-a-jwt')).isNull();
      check(JwtPayloadReader.expiryEpochSeconds(null)).isNull();
    });
  });

  group('JwtPayloadReader.delayUntilProactiveRefresh', () {
    test('should schedule refresh before exp using configured margin', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final exp = now.add(const Duration(hours: 4));
      final token = _jwtWithExp(exp.millisecondsSinceEpoch ~/ 1000);

      final delay = JwtPayloadReader.delayUntilProactiveRefresh(
        accessToken: token,
        margin: ConnectionConstants.hubAccessTokenProactiveRefreshMargin,
        now: now,
      );

      check(delay).isNotNull();
      check(delay!.inMinutes).equals(230);
    });

    test('should return zero delay when already inside refresh margin', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final exp = now.add(const Duration(minutes: 5));
      final token = _jwtWithExp(exp.millisecondsSinceEpoch ~/ 1000);

      final delay = JwtPayloadReader.delayUntilProactiveRefresh(
        accessToken: token,
        margin: ConnectionConstants.hubAccessTokenProactiveRefreshMargin,
        now: now,
      );

      check(delay).equals(Duration.zero);
    });
  });
}
