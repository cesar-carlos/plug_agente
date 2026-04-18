import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class _MockConnectionService extends Mock implements ConnectionService {}

void main() {
  late _MockConnectionService service;
  late ConnectToHub useCase;

  setUp(() {
    service = _MockConnectionService();
    useCase = ConnectToHub(service);
  });

  group('ConnectToHub', () {
    test('returns ValidationFailure when serverUrl is empty', () async {
      final result = await useCase('', 'agent-1', authToken: 'tok');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      verifyNever(() => service.connect(any(), any(), authToken: any(named: 'authToken')));
    });

    test('returns ValidationFailure when agentId is empty', () async {
      final result = await useCase('https://hub.example', '', authToken: 'tok');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
      verifyNever(() => service.connect(any(), any(), authToken: any(named: 'authToken')));
    });

    test('returns ConfigurationFailure when authToken is null', () async {
      final result = await useCase('https://hub.example', 'agent-1');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ConfigurationFailure>());
      verifyNever(() => service.connect(any(), any(), authToken: any(named: 'authToken')));
    });

    test('returns ConfigurationFailure when authToken is whitespace', () async {
      final result = await useCase('https://hub.example', 'agent-1', authToken: '   ');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ConfigurationFailure>());
      verifyNever(() => service.connect(any(), any(), authToken: any(named: 'authToken')));
    });

    test('delegates to connection service when inputs are valid', () async {
      when(
        () => service.connect(
          any(),
          any(),
          authToken: any(named: 'authToken'),
        ),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase(
        'https://hub.example',
        'agent-1',
        authToken: 'jwt-token',
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => service.connect(
          'https://hub.example',
          'agent-1',
          authToken: 'jwt-token',
        ),
      ).called(1);
    });
  });
}
