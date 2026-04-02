import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

class MockStreamingDatabaseGateway extends Mock implements IStreamingDatabaseGateway {}

class MockOdbcConnectionSettings extends Mock implements IOdbcConnectionSettings {}

void main() {
  setUpAll(() {
    registerFallbackValue(StreamingCancelReason.user);
  });

  group('ExecuteStreamingQuery', () {
    late MockStreamingDatabaseGateway mockGateway;
    late MockOdbcConnectionSettings mockSettings;
    late ExecuteStreamingQuery useCase;

    setUp(() {
      mockGateway = MockStreamingDatabaseGateway();
      mockSettings = MockOdbcConnectionSettings();
      when(() => mockSettings.streamingChunkSizeKb).thenReturn(2048);
      useCase = ExecuteStreamingQuery(mockGateway, mockSettings);
    });

    test('should fail when query is empty', () async {
      final result = await useCase(
        '   ',
        'DSN=Test',
        (_) async {},
      );

      expect(result.isError(), isTrue);
      verifyNever(
        () => mockGateway.executeQueryStream(any(), any(), any()),
      );
    });

    test('should fail when query is dangerous', () async {
      final result = await useCase(
        'DROP TABLE users',
        'DSN=Test',
        (_) async {},
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('expected validation failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
      verifyNever(
        () => mockGateway.executeQueryStream(any(), any(), any()),
      );
    });

    test('should call gateway for valid query', () async {
      when(
        () => mockGateway.executeQueryStream(
          any(),
          any(),
          any(),
          fetchSize: any(named: 'fetchSize'),
          chunkSizeBytes: any(named: 'chunkSizeBytes'),
        ),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase(
        ' SELECT * FROM users ',
        'DSN=Test',
        (_) async {},
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => mockGateway.executeQueryStream(
          'SELECT * FROM users',
          'DSN=Test',
          any(),
          fetchSize: 1000,
          chunkSizeBytes: 2048 * 1024,
        ),
      ).called(1);
    });

    test('should delegate cancel request to gateway', () async {
      when(
        () => mockGateway.cancelActiveStream(
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase.cancelActiveStream();

      expect(result.isSuccess(), isTrue);
      verify(() => mockGateway.cancelActiveStream()).called(1);
    });
  });
}
