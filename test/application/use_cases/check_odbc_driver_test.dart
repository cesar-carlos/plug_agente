import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:result_dart/result_dart.dart';

class MockOdbcDriverChecker extends Mock implements IOdbcDriverChecker {}

void main() {
  late MockOdbcDriverChecker checker;
  late CheckOdbcDriver useCase;

  setUp(() {
    checker = MockOdbcDriverChecker();
    useCase = CheckOdbcDriver(checker);
  });

  group('CheckOdbcDriver', () {
    test('should return ValidationFailure when driver name is empty', () async {
      final result = await useCase.call('   ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
      verifyNever(() => checker.checkDriverInstalled(any()));
    });

    test('should delegate to checker when name is non-empty', () async {
      when(() => checker.checkDriverInstalled('ODBC Driver 17')).thenAnswer(
        (_) async => const Success(true),
      );

      final result = await useCase.call('ODBC Driver 17');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), isTrue);
      verify(() => checker.checkDriverInstalled('ODBC Driver 17')).called(1);
    });
  });
}
