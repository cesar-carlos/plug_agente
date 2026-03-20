import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';

void main() {
  group('OdbcGatewayBufferExpansion', () {
    test('extractRequiredBufferBytes parses need N bytes', () {
      expect(
        OdbcGatewayBufferExpansion.extractRequiredBufferBytes(
          'Driver says you need 1234567 bytes for this result',
        ),
        1234567,
      );
      expect(
        OdbcGatewayBufferExpansion.extractRequiredBufferBytes('no match here'),
        isNull,
      );
    });

    test('calculateExpandedBufferBytes doubles when no required size', () {
      const current = 4 * 1024 * 1024;
      final next = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
        currentBufferBytes: current,
        errorMessage: 'buffer too small',
      );
      expect(next, current * 2);
    });

    test('calculateExpandedBufferBytes uses required bytes plus margin', () {
      const current = 32 * 1024 * 1024;
      final next = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
        currentBufferBytes: current,
        errorMessage: 'need 40000000 bytes',
      );
      expect(
        next,
        40000000 + OdbcGatewayBufferExpansion.bufferRetryMarginBytes,
      );
    });

    test('calculateExpandedBufferBytes caps at maxAutoExpandedBufferBytes', () {
      const current = OdbcGatewayBufferExpansion.maxAutoExpandedBufferBytes;
      final next = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
        currentBufferBytes: current,
        errorMessage: 'buffer too small',
      );
      expect(next, OdbcGatewayBufferExpansion.maxAutoExpandedBufferBytes);
    });

    test('messageIndicatesBufferTooSmall is case insensitive', () {
      expect(
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
          'BUFFER TOO SMALL for result',
        ),
        isTrue,
      );
      expect(
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall('other'),
        isFalse,
      );
    });
  });
}
