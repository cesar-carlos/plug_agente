import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';

void main() {
  group('ObjectFailureExtension', () {
    test('toDisplayMessage should return only failure message', () {
      final failure = DatabaseFailure.withContext(
        message: 'Failed to load configuration',
        cause: Exception('sqlite error'),
        context: {'operation': 'getById', 'configId': 'cfg-1'},
      );

      expect(failure.toDisplayMessage(), 'Failed to load configuration');
      expect(failure.toDisplayMessage(), isNot(contains('sqlite error')));
      expect(failure.toDisplayMessage(), isNot(contains('operation')));
    });

    test('toDisplayMessage should prefer user_message from context', () {
      final failure = ConnectionFailure.withContext(
        message: 'Login failed for user sa',
        context: {
          'reason': 'authentication_failed',
          'user_message':
              'Não foi possível autenticar no banco de dados. '
              'Verifique usuário, senha e permissões.',
        },
      );

      expect(
        failure.toDisplayMessage(),
        'Não foi possível autenticar no banco de dados. '
        'Verifique usuário, senha e permissões.',
      );
    });

    test(
      'toDisplayMessage should show user guidance for buffer too small',
      () {
        final failure = QueryExecutionFailure(
          'Buffer too small: need 60830894 bytes, got 33554432',
        );

        expect(
          failure.toDisplayMessage(),
          contains('Ative o modo streaming'),
        );
        expect(
          failure.toDisplayMessage(),
          contains('Buffer de resultados (MB)'),
        );
      },
    );

    test('toTechnicalMessage should include cause and context', () {
      final failure = DatabaseFailure.withContext(
        message: 'Failed to load configuration',
        cause: Exception('sqlite error'),
        context: {'operation': 'getById', 'configId': 'cfg-1'},
      );

      final technicalMessage = failure.toTechnicalMessage();

      expect(technicalMessage, contains('Failed to load configuration'));
      expect(technicalMessage, contains('sqlite error'));
      expect(technicalMessage, contains('operation'));
      expect(technicalMessage, contains('cfg-1'));
    });

    test('requiresModalDialog should be true for connection failures', () {
      final failure = ConnectionFailure('Unable to connect');

      expect(failure.requiresModalDialog, isTrue);
    });

    test('isUserRecoverable should reflect failure recoverability', () {
      final validationFailure = ValidationFailure('Invalid input');
      final serverFailure = ServerFailure('Unexpected server error');

      expect(validationFailure.isUserRecoverable, isTrue);
      expect(serverFailure.isUserRecoverable, isFalse);
    });
  });

  group('ExceptionToFailureExtension', () {
    test('toFailure should convert FormatException to ValidationFailure', () {
      const exception = FormatException('Bad format');

      final failure = exception.toFailure(
        context: {'operation': 'parse'},
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, 'FormatException: Bad format');
      expect(failure.cause, exception);
      expect(failure.context, containsPair('operation', 'parse'));
    });

    test(
      'toFailure should convert query-like exception to DatabaseFailure',
      () {
        final exception = Exception('SQL query failed');

        final failure = exception.toFailure(
          message: 'Failed to execute query',
          context: {'operation': 'executeQuery'},
        );

        expect(failure, isA<DatabaseFailure>());
        expect(failure.message, 'Failed to execute query');
        expect(failure.cause, exception);
        expect(failure.context, containsPair('operation', 'executeQuery'));
      },
    );
  });
}
