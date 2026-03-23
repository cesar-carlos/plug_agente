import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';

Future<ProcessResult> _neverRun(
  String _,
  List<String> _, {
  bool runInShell = false,
}) async {
  fail('processRun should not be invoked');
}

void main() {
  group('OdbcDriverChecker', () {
    test('should fail validation when driver name is empty', () async {
      final checker = OdbcDriverChecker(processRun: _neverRun);
      final result = await checker.checkDriverInstalled('   ');
      final failure = result.fold(
        (_) => fail('expected failure'),
        (Object f) => f as domain.ValidationFailure,
      );
      expect(failure.message, contains('vazio'));
    });

    test('should return failure when PowerShell exits non-zero', () async {
      final checker = OdbcDriverChecker(
        processRun:
            (String _, List<String> _, {bool runInShell = false}) async {
              return ProcessResult(0, 1, '', 'cmd failed');
            },
      );
      final result = await checker.checkDriverInstalled('SQL Server');
      final failure = result.fold(
        (_) => fail('expected success'),
        (Object f) => f as domain.ConfigurationFailure,
      );
      expect(failure.message, contains('listar drivers'));
      expect(failure.message, contains('cmd failed'));
    });

    test('should return true when stdout contains driver name', () async {
      final checker = OdbcDriverChecker(
        processRun:
            (String _, List<String> _, {bool runInShell = false}) async {
              return ProcessResult(0, 0, 'ODBC Driver 18 for SQL Server\n', '');
            },
      );
      final result = await checker.checkDriverInstalled('SQL Server');
      expect(
        result.fold((v) => v, (_) => fail('expected success')),
        isTrue,
      );
    });

    test('should return false when stdout omits driver name', () async {
      final checker = OdbcDriverChecker(
        processRun:
            (String _, List<String> _, {bool runInShell = false}) async {
              return ProcessResult(0, 0, 'Some Other Driver\n', '');
            },
      );
      final result = await checker.checkDriverInstalled('SQL Server');
      expect(
        result.fold((v) => v, (_) => fail('expected success')),
        isFalse,
      );
    });

    test('should map ProcessException to configuration failure', () async {
      final checker = OdbcDriverChecker(
        processRun:
            (String _, List<String> _, {bool runInShell = false}) async {
              throw const ProcessException('powershell', ['-Command'], 'boom');
            },
      );
      final result = await checker.checkDriverInstalled('SQL Server');
      final failure = result.fold(
        (_) => fail('expected success'),
        (Object f) => f as domain.ConfigurationFailure,
      );
      expect(failure.message, contains('PowerShell'));
    });

    test(
      'should map unexpected exceptions to configuration failure with context',
      () async {
        final checker = OdbcDriverChecker(
          processRun:
              (String _, List<String> _, {bool runInShell = false}) async {
                throw Exception('unexpected');
              },
        );
        final result = await checker.checkDriverInstalled('MyDriver');
        final failure = result.fold(
          (_) => fail('expected success'),
          (Object f) => f as domain.ConfigurationFailure,
        );
        expect(failure.message, contains('verificar driver'));
        expect(failure.context['operation'], 'checkDriverInstalled');
        expect(failure.context['driverName'], 'MyDriver');
        expect(failure.cause, isA<Exception>());
      },
    );
  });
}
