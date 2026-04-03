import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/errors/failure_converter.dart';

void main() {
  group('FailureConverter', () {
    group('convert', () {
      test('should convert FormatException to ValidationFailure', () {
        const exception = FormatException('Invalid format');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'test',
        );

        expect(failure, isA<ValidationFailure>());
        expect(failure.message, contains('Invalid format'));
        expect(failure.cause, equals(exception));
        expect(failure.context, {'operation': 'test'});
      });

      test('should convert ArgumentError to ValidationFailure', () {
        final exception = ArgumentError('Invalid argument');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'validate',
        );

        expect(failure, isA<ValidationFailure>());
        expect(failure.cause, equals(exception));
      });

      test('should convert StateError to ValidationFailure', () {
        final exception = StateError('Bad state');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'test',
        );

        expect(failure, isA<ValidationFailure>());
      });

      test('should convert SocketException to NetworkFailure', () {
        const exception = SocketException('Connection refused');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'connect',
        );

        expect(failure, isA<NetworkFailure>());
        expect(failure.cause, equals(exception));
      });

      test('should enrich SocketException context with address', () {
        final exception = SocketException(
          'Connection failed',
          osError: const OSError('Connection refused', 1),
          address: InternetAddress.loopbackIPv4,
        );
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'connect',
        );

        expect(failure, isA<NetworkFailure>());
        expect(failure.context, containsPair('operation', 'connect'));
        expect(failure.context.containsKey('address'), isTrue);
      });

      test('should convert ODBC exception to DatabaseFailure', () {
        final exception = Exception('ODBC error occurred');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'query',
        );

        expect(failure, isA<DatabaseFailure>());
        expect(failure.cause, equals(exception));
      });

      test('should convert connection error to ConnectionFailure', () {
        final exception = Exception('Failed to connect to database');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'connect',
        );

        expect(failure, isA<ConnectionFailure>());
      });

      test('should convert SQL error to QueryExecutionFailure', () {
        final exception = Exception('SQL syntax error near SELECT');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'execute',
        );

        expect(failure, isA<QueryExecutionFailure>());
      });

      test('should convert network error to NetworkFailure', () {
        final exception = Exception('Network timeout');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'fetch',
        );

        expect(failure, isA<NetworkFailure>());
      });

      test('should convert unknown exception to ServerFailure', () {
        final exception = Exception('Unknown error');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'process',
        );

        expect(failure, isA<ServerFailure>());
      });

      test('should include additionalContext in converted failure', () {
        final exception = Exception('Test error');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'test',
          additionalContext: {'retry': 3, 'timeout': 30},
        );

        expect(failure.context, containsPair('operation', 'test'));
        expect(failure.context, containsPair('retry', 3));
        expect(failure.context, containsPair('timeout', 30));
      });

      test('should omit operation in context when operation is null', () {
        final exception = Exception('orphan');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          additionalContext: {'k': 1},
        );

        expect(failure.context.containsKey('operation'), isFalse);
        expect(failure.context, containsPair('k', 1));
      });

      test('should map generic ODBC error to DatabaseFailure', () {
        final exception = Exception('ODBC driver returned error 08001');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'query',
        );

        expect(failure, isA<DatabaseFailure>());
      });

      test('should map ODBC connection errors to ConnectionFailure', () {
        final exception = Exception('ODBC connection refused');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'connect',
        );

        expect(failure, isA<ConnectionFailure>());
      });

      test('should map ODBC query timeout to QueryExecutionFailure with timeout context', () {
        final exception = Exception('ODBC database query timeout');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'execute',
        );

        expect(failure, isA<QueryExecutionFailure>());
        expect(failure.context['timeout'], isTrue);
        expect(failure.context['timeout_stage'], 'sql');
      });

      test('should map transport timeout to NetworkFailure with timeout context', () {
        final exception = Exception('network timeout while reading');
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
          operation: 'fetch',
        );

        expect(failure, isA<NetworkFailure>());
        expect(failure.context['timeout'], isTrue);
        expect(failure.context['timeout_stage'], 'transport');
      });

      test('should use default message when exception string is empty', () {
        final exception = _EmptyStringException();
        final stackTrace = StackTrace.current;

        final failure = FailureConverter.convert(
          exception,
          stackTrace,
        );

        expect(failure.message, 'An error occurred');
      });
    });

    group('withContext', () {
      test('should enrich existing failure with additional context', () {
        final exception = ValidationFailure('Test error');
        final stackTrace = StackTrace.current;

        final enrichedFailure = FailureConverter.withContext(
          exception,
          stackTrace,
          message: 'Enriched error message',
          context: {'key': 'value'},
        );

        expect(enrichedFailure, isA<ValidationFailure>());
        expect(enrichedFailure.message, equals('Enriched error message'));
        expect(enrichedFailure.context, containsPair('key', 'value'));
      });

      test('should preserve cause from original failure', () {
        final originalCause = Exception('Original cause');
        final exception = ValidationFailure.withContext(
          message: 'Test',
          cause: originalCause,
        );
        final stackTrace = StackTrace.current;

        final enrichedFailure = FailureConverter.withContext(
          exception,
          stackTrace,
          message: 'Enriched',
        );

        expect(enrichedFailure.cause, equals(originalCause));
      });

      test('should map unknown Failure subtype to ServerFailure when enriching', () {
        final exception = NotFoundFailure.withContext(
          message: 'missing',
        );
        final stackTrace = StackTrace.current;

        final enrichedFailure = FailureConverter.withContext(
          exception,
          stackTrace,
          message: 'wrapped',
          context: {'layer': 'infra'},
        );

        expect(enrichedFailure, isA<ServerFailure>());
        expect(enrichedFailure.message, 'wrapped');
        expect(enrichedFailure.context['layer'], 'infra');
      });

      test('should enrich after convert when exception is not Failure', () {
        final stackTrace = StackTrace.current;

        final enrichedFailure = FailureConverter.withContext(
          Exception('x'),
          stackTrace,
          message: 'outer',
          context: {'n': 2},
        );

        expect(enrichedFailure.message, 'outer');
        expect(enrichedFailure.context['n'], 2);
      });
    });
  });
}

class _EmptyStringException implements Exception {
  @override
  String toString() => '';
}
