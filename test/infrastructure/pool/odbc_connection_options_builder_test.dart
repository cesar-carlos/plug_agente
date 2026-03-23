import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';

class _MockSettings extends Mock implements IOdbcConnectionSettings {}

void main() {
  group('OdbcConnectionOptionsBuilder', () {
    test('clampedMaxResultBufferMb uses default when raw is below minimum', () {
      final settings = _MockSettings();
      when(() => settings.maxResultBufferMb).thenReturn(0);

      final mb = OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(
        settings,
      );
      expect(
        mb,
        ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024),
      );
    });

    test('clampedMaxResultBufferMb caps at 128', () {
      final settings = _MockSettings();
      when(() => settings.maxResultBufferMb).thenReturn(256);

      expect(
        OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(settings),
        128,
      );
    });

    test('forQueryExecution keeps initial buffer within max', () {
      final settings = _MockSettings();
      when(() => settings.maxResultBufferMb).thenReturn(8);
      when(() => settings.loginTimeoutSeconds).thenReturn(30);

      final options = OdbcConnectionOptionsBuilder.forQueryExecution(settings);
      expect(options.maxResultBufferBytes, 8 * 1024 * 1024);
      expect(
        options.initialResultBufferBytes! <= options.maxResultBufferBytes!,
        isTrue,
      );
    });

    test(
      'effectiveLoginTimeoutSeconds uses default when setting is non-positive',
      () {
        final settings = _MockSettings();
        when(() => settings.maxResultBufferMb).thenReturn(32);
        when(() => settings.loginTimeoutSeconds).thenReturn(0);

        expect(
          OdbcConnectionOptionsBuilder.effectiveLoginTimeoutSeconds(settings),
          ConnectionConstants.defaultLoginTimeout.inSeconds,
        );

        final options = OdbcConnectionOptionsBuilder.forQueryExecution(
          settings,
        );
        expect(
          options.loginTimeout,
          ConnectionConstants.defaultLoginTimeout,
        );
      },
    );
  });
}
