import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';

void main() {
  group('OdbcErrorInspector', () {
    test('extracts structured message and sqlstate from wrapped ODBC error', () {
      const error = ConnectionError(
        message: 'login timeout',
        sqlState: 'HYT00',
        nativeCode: 121,
      );
      final failure = domain.ConnectionFailure.withContext(
        message: 'wrapped connection failure',
        cause: error,
      );

      expect(OdbcErrorInspector.message(failure), 'login timeout');
      expect(OdbcErrorInspector.sqlState(failure), 'HYT00');
      expect(OdbcErrorInspector.nativeCode(failure), 121);
      expect(OdbcErrorInspector.isTimeout(failure), isTrue);
    });

    test('extracts structured values from failure context when cause is absent', () {
      final failure = domain.QueryExecutionFailure.withContext(
        message: 'query failed',
        context: {
          'odbc_sql_state': 'hyt01',
          'odbc_native_code': '100000',
        },
      );

      expect(OdbcErrorInspector.sqlState(failure), 'HYT01');
      expect(OdbcErrorInspector.nativeCode(failure), 100000);
      expect(OdbcErrorInspector.isTimeout(failure), isTrue);
      expect(OdbcErrorInspector.isInvalidConnectionId(failure), isTrue);
    });

    test('recognizes invalid connection id from nested context error', () {
      final failure = domain.QueryExecutionFailure.withContext(
        message: 'stale pooled handle',
        context: const {
          'error': ConnectionError(message: 'Invalid connection ID: 1000000'),
        },
      );

      expect(
        OdbcErrorInspector.message(failure),
        'Invalid connection ID: 1000000',
      );
      expect(OdbcErrorInspector.isInvalidConnectionId(failure), isTrue);
    });

    test('recognizes plain TimeoutException without ODBC metadata', () {
      expect(
        OdbcErrorInspector.isTimeout(
          TimeoutException('connect timeout'),
        ),
        isTrue,
      );
    });
  });
}
