import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_options_resolver.dart';
import 'package:plug_agente/domain/entities/query_request.dart';

void main() {
  group('resolveMaxRows', () {
    test('uses negotiated max when options omit max_rows', () {
      expect(resolveMaxRows(const {}, 100), 100);
    });

    test('caps requested max_rows at negotiated limit', () {
      expect(
        resolveMaxRows({
          'options': {'max_rows': 50},
        }, 100),
        50,
      );
      expect(
        resolveMaxRows({
          'options': {'max_rows': 200},
        }, 100),
        100,
      );
    });
  });

  group('resolveMultiResult', () {
    test('is true only when options.multi_result is true', () {
      expect(resolveMultiResult(const {}), isFalse);
      expect(
        resolveMultiResult({
          'options': {'multi_result': true},
        }),
        isTrue,
      );
    });
  });

  group('resolveRequestedTimeoutMs', () {
    test('returns timeout_ms when positive', () {
      expect(
        resolveRequestedTimeoutMs({
          'options': {'timeout_ms': 5000},
        }),
        5000,
      );
    });

    test('returns 0 when timeout_ms is absent', () {
      expect(resolveRequestedTimeoutMs(const {}), 0);
    });
  });

  group('resolveSqlHandlingMode', () {
    test('defaults to managed when options are absent', () {
      final resolution = resolveSqlHandlingMode(const {});
      expect(resolution.hasError, isFalse);
      expect(resolution.sqlHandlingMode, SqlHandlingMode.managed);
    });

    test('resolves execution_mode preserve', () {
      final resolution = resolveSqlHandlingMode({
        'options': {'execution_mode': 'preserve'},
      });
      expect(resolution.hasError, isFalse);
      expect(resolution.sqlHandlingMode, SqlHandlingMode.preserve);
    });

    test('accepts deprecated preserve_sql alias', () {
      final resolution = resolveSqlHandlingMode({
        'options': {'preserve_sql': true},
      });
      expect(resolution.hasError, isFalse);
      expect(resolution.sqlHandlingMode, SqlHandlingMode.preserve);
    });

    test('rejects preserve combined with pagination options', () {
      final resolution = resolveSqlHandlingMode({
        'options': {
          'execution_mode': 'preserve',
          'page': 1,
          'page_size': 25,
        },
      });
      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'execution_mode "preserve" cannot be combined with page, page_size, or cursor',
      );
    });
  });
}
