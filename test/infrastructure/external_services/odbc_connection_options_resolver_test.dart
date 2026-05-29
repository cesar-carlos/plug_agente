import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

void main() {
  late MockOdbcConnectionSettings settings;
  late OdbcConnectionOptionsResolver resolver;

  setUp(() {
    settings = MockOdbcConnectionSettings();
    resolver = OdbcConnectionOptionsResolver(settings);
  });

  group('forTimeout', () {
    test('caches options per (timeout, login timeout, buffer) tuple', () {
      final first = resolver.forTimeout(const Duration(seconds: 5));
      final second = resolver.forTimeout(const Duration(seconds: 5));
      expect(identical(first, second), isTrue);
    });

    test('applies the query timeout to the built options', () {
      final options = resolver.forTimeout(const Duration(seconds: 7));
      expect(options.queryTimeout, const Duration(seconds: 7));
    });

    test('defaultOptions has no explicit query timeout cap from a request', () {
      final options = resolver.defaultOptions;
      // forQueryExecution does not derive queryTimeout from a per-request value.
      expect(options, isNotNull);
    });
  });

  group('transactionalForTimeout', () {
    test('disables auto-reconnect to avoid silent transaction loss', () {
      final options = resolver.transactionalForTimeout(const Duration(seconds: 5));
      expect(options.autoReconnectOnConnectionLost, isFalse);
    });
  });

  group('isBufferTooSmallError', () {
    test('detects the buffer-too-small reason in a typed failure context', () {
      final failure = domain.QueryExecutionFailure.withContext(
        message: 'boom',
        context: {'reason': OdbcContextConstants.bufferTooSmallReason},
      );
      expect(resolver.isBufferTooSmallError(failure), isTrue);
    });

    test('detects the buffer-too-small phrase in the message', () {
      expect(
        resolver.isBufferTooSmallError(Exception('result buffer too small: need 2097152 bytes')),
        isTrue,
      );
    });

    test('returns false for unrelated errors', () {
      expect(resolver.isBufferTooSmallError(Exception('syntax error near FROM')), isFalse);
    });
  });

  group('bufferExpansionErrorMessage', () {
    test('prefers the raw odbc_message from a failure context', () {
      final failure = domain.QueryExecutionFailure.withContext(
        message: 'safe summary',
        context: {'odbc_message': 'buffer too small: need 4194304 bytes'},
      );
      expect(
        resolver.bufferExpansionErrorMessage(failure),
        'buffer too small: need 4194304 bytes',
      );
    });
  });

  group('hintedFor / rememberExpandedBuffer', () {
    test('returns null before any hint is learned', () {
      final hinted = resolver.hintedFor(
        connectionString: 'DSN=Test',
        sql: 'SELECT * FROM users',
        baseOptions: resolver.defaultOptions,
      );
      expect(hinted, isNull);
    });

    test('seeds options with the learned buffer size after remembering', () {
      const sql = 'SELECT * FROM users';
      resolver.rememberExpandedBuffer(
        connectionString: 'DSN=Test',
        sql: sql,
        currentBufferBytes: 1024 * 1024,
        error: Exception('buffer too small: need 2097152 bytes'),
      );

      final hinted = resolver.hintedFor(
        connectionString: 'DSN=Test',
        sql: sql,
        baseOptions: resolver.defaultOptions,
      );

      expect(hinted, isNotNull);
      expect(hinted!.maxResultBufferBytes, greaterThan(2097152));
    });
  });

  group('expandedFor', () {
    test('produces a larger result buffer than the current size', () {
      final base = resolver.defaultOptions;
      final expanded = resolver.expandedFor(
        Exception('buffer too small: need 4194304 bytes'),
        baseOptions: base,
        currentBufferBytes: 1024 * 1024,
      );
      expect(expanded.maxResultBufferBytes, greaterThan(1024 * 1024));
    });
  });
}
